# NetworkManager

Best choice for laptops: tray toggle, on-demand, no sudo for day-to-day use, and it's the
only method that integrates with systemd-resolved without a helper script.

## Prerequisites

```bash
ls /usr/libexec/nm-openvpn-service /usr/lib/NetworkManager/nm-openvpn-service 2>/dev/null
dpkg -l network-manager-openvpn network-manager-openvpn-gnome 2>/dev/null | grep ^ii
```

Without the plugin the import fails outright. `network-manager-openvpn-gnome` adds the tray
UI; without it the connection works but only via `nmcli`.

## Import

```bash
nmcli connection import type openvpn file <working-config>
```

Usually succeeds **without sudo** — polkit grants this to an active desktop session. Try it
before asking the user to run anything.

Import extracts the inline `<ca>`, `<cert>`, `<key>`, and `<tls-auth>` blocks into
`~/.cert/nm-openvpn/` and rewrites the connection to reference those files. This is why the
original profile becomes unnecessary afterwards.

## What import silently drops

This is the part that isn't guessable and causes most post-import confusion. NetworkManager
models a fixed set of OpenVPN options; anything outside that set is discarded without
warning, and some things it does model are left unset.

| What | State after import | Fix |
|---|---|---|
| `pull-filter` | **Dropped** | Use `ipv4.never-default` instead |
| `tls-cert-profile`, `providers` | **Dropped** | Rarely needed post-connect; see below |
| `auth-user-pass <file>` | Path discarded, file never read | Set `vpn.user-name` + `vpn.secrets` |
| `vpn.user-name` | Empty | Set explicitly |
| `password-flags` | `1` (prompt every time) | Set to `0` and store the secret |
| `connection.autoconnect` | `yes` | Set to `no` for on-demand |
| `redirect-gateway` | Honored → full tunnel | `ipv4.never-default yes` |

Always inspect after importing rather than assuming:

```bash
nmcli -f vpn.data con show <name> | tr ',' '\n'
nmcli -f vpn.user-name,ipv4.never-default,connection.autoconnect con show <name>
```

On the dropped compat options: they matter for the *handshake*, and if the manual connect
already succeeded, the negotiated result (visible in the log's `Control Channel:` line) is
usually reached without them. If import breaks a connection that worked manually, that's
the first thing to suspect.

## Credentials

```bash
nmcli con modify <name> vpn.user-name "<username>"
nmcli con modify <name> +vpn.data "password-flags=0"
nmcli con modify <name> vpn.secrets "password=<password>"
```

All three are needed. `password-flags=0` means "stored"; without it NetworkManager prompts
on every connect regardless of a stored secret.

The password lands in `/etc/NetworkManager/system-connections/<name>.nmconnection`
(root-only). Tell the user, since it's now a second copy alongside their creds file.

The password appears in the process list briefly during the `nmcli` call. On a personal
machine that's acceptable; on a shared or multi-user host, prefer `nmcli --ask con modify`
or let the user enter it in the GUI.

## Split tunneling

```bash
nmcli con modify <name> ipv4.never-default yes
nmcli con modify <name> ipv6.never-default yes
```

This is NetworkManager's equivalent of `pull-filter ignore "redirect-gateway"`. The server's
pushed subnet routes are still installed; only the default route is refused.

Set the IPv6 one too. A tunnel that leaks the v6 default route while v4 is split produces
intermittent, hard-to-diagnose behavior on dual-stack networks.

Verify by confirming the default route still points at the physical interface:

```bash
ip route show default          # should be the LAN gateway, not the tunnel
ip route show dev tun0         # should list the pushed subnets
```

For a full tunnel, set `never-default no` — but check for other VPNs first (`ip link`),
since Tailscale, Docker, and corporate clients all contend for the default route.

## Split DNS

The piece that most often silently doesn't work.

A VPN link that isn't the default route gets no DNS traffic from systemd-resolved unless it
has a **search domain** to match against. Without one you get:

```
Link 5 (tun0)
    Current Scopes: none          ← DNS accepted, then ignored
```

The pushed servers are registered and never queried. Routing works, internal hostnames
don't resolve, and nothing reports an error.

```bash
nmcli con modify <name> ipv4.dns "<dns1> <dns2>"
nmcli con modify <name> ipv4.dns-search "<internal.domain>"
nmcli con modify <name> ipv4.dns-priority 50
nmcli con down <name> && sleep 2 && nmcli con up <name>
```

Reactivation is required — DNS settings aren't applied live.

`dns-priority 50` keeps the VPN below the physical link for general queries while the search
domain routes its own domain to the tunnel. That's true split DNS: internal names go
inside, everything else stays on the local resolver.

### Finding the internal domain

Users frequently don't know it. Ask the internal DNS server for the gateway's reverse
record — this works as soon as the tunnel is up, before DNS is configured:

```bash
dig +short -x <internal-gateway-ip> @<pushed-dns-ip>
# → unifi.company.com     ⇒ search domain is company.com
```

If PTR is empty, try the DHCP domain on another host on that network, or just ask. As a
last resort `ipv4.dns-search "~."` routes *all* DNS through the tunnel — it works, but it
sends public queries over the VPN too, so prefer a real domain.

### Verify both directions

```bash
resolvectl status tun0 | head -8      # expect: Current Scopes: DNS, and the domain
resolvectl query <internal-host>      # expect: link: tun0
resolvectl query example.com          # expect: link: <physical iface>
```

Checking only the internal name hides a config that has hijacked all DNS. Both directions
or it isn't verified.

## Daily use

```bash
nmcli con up <name>
nmcli con down <name>
```

Or the tray applet → VPN → connection name. Set `connection.autoconnect no` for on-demand.

## Troubleshooting

**Prompts for a password despite storing one** — `password-flags` isn't `0`. Re-check
`nmcli -f vpn.data con show <name> | tr ',' '\n' | grep password-flags`.

**Works manually but not via NM** — a dropped compat option. Compare `vpn.data` against the
working config; add back via `+vpn.data "key=value"`.

**Connects but no internal traffic** — check `ip route show dev tun0` against the
`PUSH_REPLY` route list from the manual connect.

**Logs** — `journalctl -u NetworkManager -f --since "5 min ago"`, filtered on `nm-openvpn`.
Less detailed than a manual `verb 3` run, which is why the manual connect comes first.
