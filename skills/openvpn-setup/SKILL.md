---
name: openvpn-setup
description: Set up, connect, and troubleshoot an OpenVPN client on Linux from a .ovpn profile — legacy-config fixes for OpenVPN 2.6/OpenSSL 3 (incl. the misleading AUTH_FAILED cipher error), NetworkManager or systemd, split tunnel and split DNS.
---

# OpenVPN client setup on Linux

Getting an OpenVPN profile working is rarely just "run openvpn". Most `.ovpn` files in
circulation were exported years ago by an appliance that hasn't updated its template, so
they carry directives that OpenVPN 2.6 and OpenSSL 3 now refuse or ignore. The failures
they produce are actively misleading — the single most common one announces itself as an
authentication failure when the credentials are perfect.

So the shape of this work is: get a connection with maximum diagnostic visibility first,
read the log properly, and only then make it permanent and convenient. Skipping to the
GUI import is the main way this goes wrong, because NetworkManager swallows the log that
tells you what's actually broken.

## Workflow

### 1. Read the inputs, and never edit the original

Read the `.ovpn` and any credentials file. Look for a companion creds file in the same
directory — it's usually two lines, username then password.

Copy the profile to a working file (`<name>.conf`) and make every change there. The
original is the user's only pristine copy from their provider, and you will be adding and
removing directives experimentally. Keeping it clean means a bad edit is never
unrecoverable.

`chmod 600` the working copy and the creds file immediately if they contain an inline
`<key>` block or a password. These are private keys and passwords sitting in a user's home
directory, frequently world-readable straight out of a download folder.

### 2. Preflight

Run `scripts/preflight.sh <config> [creds]`. It reports the OpenVPN and OpenSSL versions,
which client tooling is installed, flags every directive in the profile known to break on
modern stacks, and tests whether the server's port is actually reachable.

Reachability matters before anything else because a firewalled or wrong `remote` produces
timeouts that look like config problems and waste a lot of time. If the port is closed,
stop and sort that out first.

### 3. Modernize the config

Apply the fixes preflight flagged. `references/compatibility.md` has the full table of
directive → symptom → fix; the short version is that a lone `cipher` line needs a proper
`data-ciphers` list, any compression directive needs `allow-compression yes`, and old CAs
need the legacy OpenSSL provider.

Prefer widening over pinning. A `data-ciphers` list offering GCM, ChaCha20 and CBC lets the
server pick what it actually supports; pinning the one cipher named in a stale config is
how you get a negotiation failure against a server that upgraded years ago.

### 4. Connect manually — this is the diagnostic step

```
sudo openvpn --config <working-config>
```

`sudo` normally needs a password that you cannot supply, so hand this command to the user
and ask them to paste the log back. In Claude Code, suggest they prefix it with `!` so the
output lands in the conversation.

Do this before any import even when you're confident, because `verb 3` output is the only
place the real failure is stated. Wait for `Initialization Sequence Completed`.

### 5. Read the log properly

The log narrates the connection in stages, and where it stops tells you what's wrong:

| Last thing you see | What's actually broken |
|---|---|
| No `TCP/UDP connection established` | Network path, wrong port, or wrong protocol (tcp vs udp) |
| `VERIFY ERROR` / `certificate signature failure` | CA trust or an OpenSSL 3 policy rejection — not a bad cert |
| `Peer Connection Initiated`, then `AUTH_FAILED` | Read the text *after* `AUTH_FAILED` before assuming credentials |
| `PUSH_REPLY` received, then stalls | Routing or a compression mismatch |
| `Initialization Sequence Completed` | Connected — move to persistence |

`AUTH_FAILED,Data channel cipher negotiation failed (no shared cipher)` is the trap worth
knowing by name. It is a cipher problem, not a credentials problem, and it appears when the
config pins a cipher the server no longer offers. Widen `data-ciphers`. Users who see
`AUTH_FAILED` reasonably conclude their password is wrong and start resetting it, so say
plainly that the credentials are fine.

Note what the `PUSH_REPLY` line contains — pushed routes, DNS servers, and the negotiated
cipher. Those pushed routes are the list of subnets that should reach the VPN, and you'll
verify against them in step 8.

### 6. Choose how it should run

Once connected, ask how they want it to run day to day. The three options suit genuinely
different situations:

- **NetworkManager** — tray toggle, on-demand, handles DNS natively. Right for laptops.
  See `references/networkmanager.md`.
- **systemd** — always-on, starts at boot. Right for servers and always-connected
  workstations. See `references/systemd.md`.
- **Manual** — keep running the command above. Fine for occasional use.

### 7. Default to split tunneling, and say so

If the config has `redirect-gateway` or the server pushes a default route, **all** the
user's traffic will cross the VPN. That is often not what someone wants from a VPN that
exists to reach an office network: it slows general browsing, routes personal traffic
through an employer's egress, and fights with anything else claiming the default route
(Tailscale and Docker both do).

Default to split tunneling — only the pushed internal subnets go through the tunnel. State
the assumption in one line and offer the switch, rather than asking up front; it's the
safer default and it's a one-setting change either way.

The setting is method-specific (`ipv4.never-default` for NetworkManager, `pull-filter` for
raw OpenVPN) and covered in the reference files. Check for other VPNs — `ip route show` and
`ip link` — and mention any you find, since route conflicts surface later as confusing
partial connectivity.

### 8. Verify, including DNS

Run `scripts/verify.sh [internal-host] [public-host]`. It checks the tunnel is up, whether
the default route is inside or outside the tunnel, which pushed subnets are routed, and —
critically — whether DNS resolves in both directions.

DNS is the piece that silently doesn't work. Routing can be perfect while internal
hostnames fail, because `dhcp-option DNS` from the server needs a resolver integration that
raw OpenVPN doesn't have. `resolvectl status tun0` reporting `Current Scopes: none` means
the pushed DNS was accepted and then ignored.

Correct split DNS means internal names resolve via the tunnel *and* public names still
resolve via the local resolver. Verify both — only checking the internal one hides a
config that has quietly hijacked all DNS.

systemd-resolved will not send queries to a non-default link without a **search domain**,
so you usually need the internal domain name. If the user doesn't know it, ask the internal
DNS server for the reverse record of the gateway:

```
dig +short -x <internal-gateway-ip> @<pushed-dns-ip>
```

That typically returns something like `router.company.com`, and the domain half is what you
want. `references/networkmanager.md` covers applying it.

### 9. Close out honestly

Report what's configured and what you verified — the working state, not just the commands
you ran.

Then account for the secrets. Setup routinely leaves the password in two or three places
and the private key in more, and users don't track this. Say where each copy ended up and
which are now unused.

Don't delete the originals unless asked. When the user does ask, check first that the
persistence method has its own copies of everything it needs (NetworkManager copies certs
to `~/.cert/nm-openvpn/`; systemd needs the config to stay where it is), and note that the
original profile is their only copy for setting up another device.

## Behavior that matters here

**Hand over privileged commands rather than failing on them.** `sudo` needs a password you
don't have. Give the user the exact command and ask for the output. Notably, `nmcli
connection import` usually works *without* sudo via polkit, so try it before assuming.

**Verify claims about the network.** "Connected" is not the same as "can reach internal
hosts", which is not the same as "internal hostnames resolve". Each is a separate check and
they fail independently. Run them.

**Explain the misleading errors.** A user who has seen `AUTH_FAILED` believes their
password is wrong. Say explicitly that it isn't, and why.

## Reference files

- `references/compatibility.md` — legacy directives, the errors they cause on OpenVPN
  2.6/OpenSSL 3, and the fixes. Read when a connection fails or a config looks dated.
- `references/networkmanager.md` — import, the settings the import silently drops, split
  tunnel, split DNS. Read before any NetworkManager work; the dropped-settings list is not
  guessable.
- `references/systemd.md` — always-on service, DNS via update-systemd-resolved.
