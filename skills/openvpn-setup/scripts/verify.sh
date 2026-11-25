#!/usr/bin/env bash
# Verify a live OpenVPN tunnel: interface, routing mode, pushed subnets, split DNS.
# Usage: verify.sh [internal-host-or-ip] [public-host]
#
# Routing and DNS fail independently - a tunnel can be up and routing perfectly while
# internal hostnames never resolve. Each section below is a separate check.

set -uo pipefail

INTERNAL="${1:-}"
PUBLIC="${2:-example.com}"

say() { printf '\n=== %s ===\n' "$1"; }
ok()  { echo "[ok] $1"; }
bad() { echo "[!!] $1"; }
inf() { echo "[i]  $1"; }

say "Tunnel"
TUN=$(ip -o link show type tun 2>/dev/null | awk -F': ' '{print $2}' | grep -v tailscale | head -1)
if [[ -z "$TUN" ]]; then
  bad "no tun interface - VPN is not connected"
  exit 1
fi
ok "$TUN up: $(ip -4 -o addr show "$TUN" | awk '{print $4}' | head -1)"

if command -v nmcli >/dev/null; then
  nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null | awk -F: '$2=="vpn"{print "[i]  NM connection: "$1" ("$3")"}'
fi

say "Routing"
DEF=$(ip route show default | head -1)
inf "default: $DEF"
if grep -q "$TUN" <<<"$DEF"; then
  inf "FULL TUNNEL - all traffic goes through the VPN"
  inf "for split tunnel: nmcli con modify <name> ipv4.never-default yes"
else
  ok "SPLIT TUNNEL - default route stays on the physical link"
fi

N=$(ip route show dev "$TUN" 2>/dev/null | grep -c via)
if [[ "$N" -gt 0 ]]; then
  ok "$N subnet route(s) via the tunnel:"
  ip route show dev "$TUN" | grep via | sed 's/^/       /'
else
  bad "no subnet routes via $TUN - compare against the PUSH_REPLY line in the connect log"
fi

# Other VPNs contend for the default route; surface them before they cause confusion.
OTHER=$(ip -o link show | awk -F': ' '{print $2}' | grep -E 'tailscale|wg[0-9]|ppp' | tr '\n' ' ')
[[ -n "$OTHER" ]] && inf "other VPN interfaces present: $OTHER (may contend for routes)"

say "DNS registration"
if command -v resolvectl >/dev/null; then
  ST=$(resolvectl status "$TUN" 2>/dev/null)
  SRV=$(grep 'DNS Servers' <<<"$ST" | cut -d: -f2- | xargs)
  DOM=$(grep 'DNS Domain' <<<"$ST" | cut -d: -f2- | xargs)
  if grep -q 'Current Scopes: none' <<<"$ST"; then
    bad "$TUN has DNS servers registered but scope 'none' - they will never be queried"
    inf "cause: a non-default link needs a search domain for systemd-resolved to use it"
    inf "fix : nmcli con modify <name> ipv4.dns-search \"<internal.domain>\" && reactivate"
    [[ -n "$SRV" ]] && inf "find the domain: dig +short -x <internal-gw> @${SRV%% *}"
  elif grep -q 'Current Scopes: DNS' <<<"$ST"; then
    ok "$TUN DNS active - servers: ${SRV:-none}  domain: ${DOM:-<none>}"
    [[ -z "$DOM" ]] && bad "no search domain - internal short names still won't resolve"
  else
    bad "no DNS registered on $TUN"
  fi
else
  inf "resolvectl absent; resolvers: $(grep ^nameserver /etc/resolv.conf | xargs)"
fi

say "DNS resolution (both directions)"
if command -v resolvectl >/dev/null; then
  if [[ -n "$INTERNAL" ]]; then
    R=$(timeout 8 resolvectl query "$INTERNAL" 2>&1 | head -1)
    if grep -q "link: $TUN" <<<"$R"; then
      ok "internal '$INTERNAL' resolves via the tunnel"
    elif grep -qi 'not found\|failed' <<<"$R"; then
      bad "internal '$INTERNAL' does not resolve: $R"
    else
      bad "internal '$INTERNAL' resolved OUTSIDE the tunnel: $R"
    fi
  else
    inf "pass an internal hostname as arg 1 to check internal resolution"
  fi

  R=$(timeout 8 resolvectl query "$PUBLIC" 2>&1 | head -1)
  if grep -q "link: $TUN" <<<"$R"; then
    bad "public '$PUBLIC' resolves through the TUNNEL - the VPN has hijacked all DNS"
    inf "for split DNS use a specific ipv4.dns-search domain, not \"~.\""
  elif grep -qi 'not found\|failed' <<<"$R"; then
    bad "public '$PUBLIC' does not resolve - general DNS is broken"
  else
    ok "public '$PUBLIC' resolves via the local resolver (correct for split DNS)"
  fi
fi

say "Connectivity"
GW=$(ip route show dev "$TUN" | grep -oP 'via \K[\d.]+' | head -1)
if [[ -n "$GW" ]]; then
  timeout 6 ping -c2 -W2 "$GW" >/dev/null 2>&1 \
    && ok "tunnel gateway $GW reachable" || bad "tunnel gateway $GW unreachable"
fi
if [[ -n "$INTERNAL" ]]; then
  timeout 6 ping -c2 -W2 "$INTERNAL" >/dev/null 2>&1 \
    && ok "internal host $INTERNAL reachable" || inf "$INTERNAL did not answer ping (may just block ICMP)"
fi
