# SharkTrustX Portal Architecture

## Overview

SharkTrustX is a root Mako Server application that combines four services:

- a browser portal for system and zone administrators;
- authoritative Domain Name System (DNS) data for registered zones;
- a current HTTPS/JSON device API used for enrollment, address updates, ACME
  DNS-01 records, and reverse connections; and
- certificate management for the portal and its zones.

The deployable application is `www/`. Its `.preload` file is the composition
root. It validates host configuration, initializes persistent state, rebuilds
BIND data, starts certificate handling, and installs host-based request
routing.

## Runtime ownership

| Component | Owner and lifecycle |
| --- | --- |
| Application startup | `www/.preload` starts work in a BAS thread and exports the small `app` interface used by private pages. |
| Database | `ZoneDB.lua` opens the database created or migrated by `CreateDB.lua`. One persistent writer connection serializes mutations. |
| DNS | `.preload` renders files in `/etc/bind/zones/`, updates `named.conf.local`, and calls `rndc reconfig` or `rndc reload`. |
| Certificates | `CertUpdater.lua` stores ACME account and certificate state under the writable home `acmecert/` directory and installs active certificates. |
| Reverse connections | `RevConnBridge.lua` owns device sockets, temporary names, browser queues, timeouts, and cleanup. |
| Microsoft Entra single sign-on | `ms-sso.lua` validates OpenID Connect results. `.preload` caches one configured provider per zone. |
| Browser routes | `.lua/www/admin.lua` and `.lua/www/zones.lua` render private HTML templates through the shared light dashboard shell. |
| Client diagnostics | `ClientLog.lua` formats device and observed peer addresses. Request handlers pass the scoped logger to deferred DNS/database callbacks and reverse connections; the logger retains only address strings. |
| Unload | `onunload()` closes cached Entra providers. Mako owns the remaining application teardown. |

Mutable data does not belong in the ZIP. The deployment working directory
contains `mako.conf`, `zones.db`, ACME and certificate state, and backups. BIND
state remains under `/etc/bind/`.

## Request routing

The application is mounted at the root with priority 1 or higher. The fallback
directory in `.preload` dispatches requests by host name:

1. The configured service host opens the system-administration portal.
2. A registered zone host opens that zone's portal.
3. A recognized device-plus-zone host is handed to the reverse bridge.
4. A direct private-IP request on a private deployment opens administration.
5. Other direct-IP requests redirect to the configured service host.

The public CSS and JavaScript files are under `www/assets/`. Private Lua source
and HTML templates remain below `www/.lua/` and are not served as static files.

## Current SharkTrust request flow

All current device operations use HTTPS `/sharktrust.lsp`. The complete wire
contract is in [`SharkTrust-Protocol.md`](SharkTrust-Protocol.md).

Before enrollment, a client uses the zone key and a request proof derived from
the zone secret. `IsAvailable` checks a proposed name but does not reserve it.
`Register` runs under a zone enrollment lock, creates a random per-device
credential, stores only its verifier, and returns the credential once.

After enrollment, the client sends the device credential as a bearer token and
adds a proof over the exact JSON body. `SharkTrust.lua` resolves the credential
to its device and zone before dispatching these commands:

| Command | Effect |
| --- | --- |
| `IsRegistered` | Confirms enrollment and updates observed access data. |
| `SetIpAddress` | Updates the local address and preserves the existing DNS mode when `dns` is omitted. |
| `SetAcmeRecord` | Publishes the exact temporary `_acme-challenge` TXT record owned by the device. |
| `RemoveAcmeRecord` | Removes that device's temporary ACME records. |
| `GetWan` | Returns the public peer address observed by the portal. |

The BAS-Resources client discovers its local IPv4 address from the trusted
portal connection. Applications do not need to configure that address for
normal enrollment or registration checks.

The request proof authenticates the exact body, but it has no server nonce,
timestamp, or counter. It therefore does not add replay rejection beyond the
protection provided by validated TLS. The protocol document records this
boundary explicitly.

## Legacy protocol boundary

`/rtoken.lsp` and `/command.lsp` remain for BACME 1.x clients. They use shared
zone credentials, process-local refresh tokens, and request data carried in
HTTP headers. They are not the design basis for new work. Their implemented
contract and limits are documented in
[`BACME-Protocol-Legacy.md`](BACME-Protocol-Legacy.md).

Removing the two endpoints also permits removal of `RefreshTokenManager.lua`
and the legacy command section in `.preload`, but that is a protocol and client
compatibility decision, not documentation cleanup.

## Database and migrations

`CreateDB.lua` creates schema version 1.5 and migrates older supported schemas
at startup. The principal tables are:

| Table | Content |
| --- | --- |
| `config` | Schema version and retained configuration values. |
| `zones` | Zone name, administrator, enrollment credentials, registration options, reverse prefix, and Entra configuration. |
| `devices` | Device name, legacy key, local and WAN addresses, DNS mode, current credential verifier, registration time, and last access. |
| `users` | Zone users, password verifier, role, registration time, and last access. |
| `UsersDevAccess` | Per-user device access assignments. |

Unique indexes protect a current device credential verifier across the whole
database and a case-insensitive device name within a zone.

All mutations go through the writer owned by `ZoneDB.lua`. Read operations use
separate short-lived connections or iterators. Callers whose HTTP response
depends on a write use a deferred response and complete it only after the
callback reports the committed result.

## Device cleanup

Zone administrators open `cleanup.html`, choose a cutoff date, and request a
preview. The server selects devices whose last access is before that cutoff and
stores a short-lived preview in the authenticated session. Removal requires an
acknowledgement and the exact preview identifier. The database operation
removes only the previewed rows that are still eligible in the same zone, then
clears reverse state and rebuilds BIND data.

This preview-and-consume design prevents a broad, stale client request from
silently expanding its deletion set.

## Sensitive zone actions

`SensitiveAction.lua` protects two zone-credential operations:

- display the zone secret on `settings.html`;
- download the generated `tokengen.c` module from `cgen.html`.

Both begin with a session-bound request token, send a one-time code to the zone
administrator's email address, limit retries, expire the challenge after ten
minutes, and grant one consumable authorization for the selected purpose.

The generated C file reconstructs an obfuscated zone secret and supplies the
proof function used by the current client. It makes static extraction harder,
but it is software obfuscation rather than a Trusted Platform Module (TPM) or
secure element.

## Certificate lifecycle

At startup, the portal rebuilds every BIND zone and starts certificate work.
Static portal names use HTTP-01. Registered zones use DNS-01 callbacks that
write and remove their TXT records through the same BIND update path.

The portal keeps staging and production ACME accounts and certificates under
separate filenames in `acmecert/`. Elliptic Curve Cryptography (ECC) keys use
the Mako TPM interface by default. `settings.acme.rsa=true` selects a software
RSA certificate key. Existing keys are reused.

## Reverse connections

An enrolled device authenticates a `GET /sharktrust.lsp` request and transfers
the socket to `RevConnBridge.lua`. A browser request for the device host is
also converted to a socket. The bridge pairs the oldest waiting browser socket
with the next device socket and then copies bytes in both directions.

The browser queue is bounded and timed. If no device socket becomes available,
the portal returns `503 Service Unavailable`. Removing a device also removes
its reverse state. Fixed prefixes come from zone or device configuration;
otherwise the bridge creates a temporary random name.

## Security boundaries

- Linux startup requires `root` because the application manages BIND.
- Device APIs require validated HTTPS and do not redirect insecure requests.
- Browser authorization is enforced by route handlers and session roles, not
  by hiding navigation links.
- Zone secret display, generated C download, deletion previews, and device
  mutations use session-bound request tokens or additional verification.
- Credentials and private keys must not appear in URLs, logs, screenshots, or
  repository files.
- Generated C reduces static-key visibility but does not create protected key
  storage.
- Windows development simulates BIND and can disable portal ACME only for an
  isolated test. It is not Linux DNS or certificate acceptance.
