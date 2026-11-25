# systemd service

For always-on connections: servers, headless boxes, workstations that should be on the VPN
from boot. On a laptop that connects on demand, NetworkManager is the better fit.

## Setup

```bash
sudo cp <working-config> /etc/openvpn/client/<name>.conf
sudo chmod 600 /etc/openvpn/client/<name>.conf
sudo systemctl enable --now openvpn-client@<name>
systemctl status openvpn-client@<name>
```

The unit name must match the filename stem: `/etc/openvpn/client/office.conf` is driven by
`openvpn-client@office`. The `openvpn-client@` template (not the older `openvpn@`) is the
current one and expects `/etc/openvpn/client/`.

## Credentials

The service is non-interactive, so credentials must come from a file:

```
auth-user-pass /etc/openvpn/client/<name>.creds
```

Two lines — username, then password. Store it under `/etc/openvpn/client/` rather than a
home directory: the service starts at boot, possibly before `/home` is mounted on systems
with encrypted or network home directories.

```bash
sudo chmod 600 /etc/openvpn/client/<name>.creds
sudo chown root:root /etc/openvpn/client/<name>.creds
```

## DNS

Raw OpenVPN accepts the server's pushed `dhcp-option DNS` and then does nothing with it —
there's no built-in systemd-resolved integration. Internal hostnames won't resolve unless
you add the helper.

```bash
sudo apt install openvpn-systemd-resolved
```

Then in the config:

```
script-security 2
setenv PATH /usr/bin:/bin:/usr/sbin:/sbin
up /etc/openvpn/update-systemd-resolved
down /etc/openvpn/update-systemd-resolved
down-pre
```

`script-security 2` is required for OpenVPN to run external scripts at all. It's scoped to
the scripts this config names, but it is a real privilege grant — only point it at the
distribution-packaged helper.

For split DNS, add a routing domain so resolved sends only that domain's queries to the
tunnel:

```
dhcp-option DOMAIN-ROUTE <internal.domain>
```

Without it, resolved won't query the tunnel's servers for anything (a non-default link with
no domain gets `Current Scopes: none`). See the DNS section of `networkmanager.md` for
finding the domain via a PTR lookup.

## Split tunneling

```
pull-filter ignore "redirect-gateway"
```

Refuses the pushed default route while keeping the pushed subnet routes. Confirm with
`ip route show default` — it should still point at the physical gateway.

To ignore other pushed directives, `pull-filter ignore "<prefix>"` matches on the start of
the pushed option string.

## Privilege downgrade

Keep these when running as a service — they drop root after the tunnel is established, so a
compromised long-running process isn't running as root:

```
user nobody
group nogroup
persist-key
persist-tun
```

`persist-key` and `persist-tun` are what make the downgrade survive a reconnect; without
them a reconnect fails because the unprivileged process can't reopen the device or reread
the key.

Remove these for a NetworkManager import — NM manages privileges itself and they conflict.

## Operation

```bash
systemctl status openvpn-client@<name>
journalctl -u openvpn-client@<name> -f
sudo systemctl restart openvpn-client@<name>
sudo systemctl disable --now openvpn-client@<name>
```

Reconnection is automatic. `ping 10` / `ping-restart 60` in most profiles means a dead
tunnel restarts within a minute; `Restart=on-failure` in the unit covers process death.

## Troubleshooting

**Fails at boot but works manually** — a race with the network. Add a drop-in:

```bash
sudo systemctl edit openvpn-client@<name>
```

```ini
[Unit]
After=network-online.target
Wants=network-online.target
```

DNS-resolved `remote` hostnames are the usual cause; an IP literal avoids it entirely.

**`Options error: --up script fails`** — missing `script-security 2`, or the helper isn't at
the path given.

**Works, then dies after a few hours** — usually renegotiation. Check the journal around the
failure; `reneg-sec 0` in the profile disables it, which is common for password-auth
servers that can't silently re-authenticate.
