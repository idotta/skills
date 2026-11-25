#!/usr/bin/env bash
# Preflight for an OpenVPN profile: tooling, legacy directives, server reachability.
# Usage: preflight.sh <config.ovpn> [credsfile]
# Exits 1 only if the config is unusable (missing/no remote). Flagged directives are
# advisory - they tell you what to fix, not that you should stop.

set -uo pipefail

CONF="${1:-}"
CREDS="${2:-}"

if [[ -z "$CONF" || ! -f "$CONF" ]]; then
  echo "usage: preflight.sh <config.ovpn> [credsfile]" >&2
  exit 1
fi

say() { printf '\n=== %s ===\n' "$1"; }
has() { grep -qiE "^[[:space:]]*$1([[:space:]]|$)" "$CONF"; }
val() { grep -iE "^[[:space:]]*$1[[:space:]]" "$CONF" | head -1 | awk '{$1=""; print $0}' | xargs; }

say "Tooling"
if command -v openvpn >/dev/null; then
  openvpn --version 2>/dev/null | head -2
else
  echo "openvpn: NOT INSTALLED  (apt install openvpn)"
fi
for t in nmcli systemctl resolvectl dig; do
  command -v "$t" >/dev/null && echo "$t: present" || echo "$t: missing"
done
if command -v nmcli >/dev/null; then
  if [[ -e /usr/libexec/nm-openvpn-service || -e /usr/lib/NetworkManager/nm-openvpn-service ]]; then
    echo "NM openvpn plugin: present"
  else
    echo "NM openvpn plugin: MISSING (apt install network-manager-openvpn-gnome)"
  fi
fi

say "Profile"
REMOTE=$(val remote)
[[ -z "$REMOTE" ]] && { echo "no 'remote' line - unusable config" >&2; exit 1; }
HOST=$(awk '{print $1}' <<<"$REMOTE")
PORT=$(awk '{print $2}' <<<"$REMOTE"); PORT=${PORT:-1194}
PROTO=$(val proto); PROTO=${PROTO:-udp}
echo "remote : $HOST:$PORT ($PROTO)"
echo "auth   : $(has auth-user-pass && echo 'password + cert' || echo 'cert only')"
for b in ca cert key tls-auth tls-crypt; do
  grep -q "<$b>" "$CONF" && echo "inline : <$b>"
done

say "Compatibility (OpenVPN 2.6 / OpenSSL 3)"
ISSUES=0
flag() { echo "[!] $1"; echo "    -> $2"; ISSUES=$((ISSUES+1)); }

if has cipher && ! has data-ciphers; then
  flag "'cipher $(val cipher)' with no data-ciphers list" \
       "add: data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC:AES-128-CBC
       (symptom: AUTH_FAILED,Data channel cipher negotiation failed - NOT a password problem)"
fi
if (has comp-lzo || has compress) && ! has allow-compression; then
  flag "compression enabled without allow-compression" "add: allow-compression yes"
fi
if grep -qiE '^[[:space:]]*(auth[[:space:]]+SHA1|cipher[[:space:]]+BF-CBC)' "$CONF"; then
  flag "legacy crypto (SHA1 / BF-CBC)" "if certs are rejected, add: tls-cert-profile insecure
       and: providers legacy default"
fi
if grep -q "<tls-auth>" "$CONF" && ! has key-direction; then
  flag "tls-auth without key-direction" "add: key-direction 1  (symptom: bad HMAC / silent timeout)"
fi
for dead in ncp-disable keysize tun-mtu-extra; do
  has "$dead" && flag "'$dead' is removed in 2.6" "delete this line (fatal: Unrecognized option)"
done
if has redirect-gateway; then
  echo "[i] redirect-gateway present - server wants ALL traffic through the VPN."
  echo "    -> for split tunnel: pull-filter ignore \"redirect-gateway\"  (or NM: ipv4.never-default yes)"
fi
[[ $ISSUES -eq 0 ]] && echo "no known-problem directives found"

say "Credentials"
if [[ -n "$CREDS" && -f "$CREDS" ]]; then
  PERM=$(stat -c '%a' "$CREDS")
  echo "file  : $CREDS (mode $PERM, $(wc -l <"$CREDS") lines)"
  echo "user  : $(head -1 "$CREDS")"
  [[ "$PERM" != "600" ]] && echo "[!] not 0600 - run: chmod 600 $CREDS"
elif has auth-user-pass; then
  echo "profile needs a username/password; none supplied"
fi
if grep -q "<key>" "$CONF"; then
  PERM=$(stat -c '%a' "$CONF")
  [[ "$PERM" != "600" ]] && echo "[!] $CONF holds a private key but is mode $PERM - run: chmod 600 $CONF"
fi

say "Reachability: $HOST:$PORT"
if [[ "$PROTO" == tcp* ]]; then
  if timeout 8 bash -c "cat < /dev/null > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
    echo "TCP $PORT reachable"
  else
    echo "[!] TCP $PORT unreachable - check firewall/remote before debugging config"
  fi
else
  echo "UDP - cannot test without a handshake; the connect attempt will tell you"
  command -v nc >/dev/null && timeout 5 nc -zvu "$HOST" "$PORT" 2>&1 | tail -1
fi

say "Next"
echo "1. apply the fixes above to a COPY of the profile (keep the original clean)"
echo "2. sudo openvpn --config <copy>   # read the log; wait for Initialization Sequence Completed"
echo "3. then pick a persistence method and run verify.sh"
