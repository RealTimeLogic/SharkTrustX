# SharkTrustX Handover Guide

## Start here

SharkTrustX is a Mako Server portal for authoritative DNS, device enrollment,
Automatic Certificate Management Environment (ACME) DNS-01 automation, zone
administration, and reverse connections to private Barracuda App Server
devices. The deployable application is [`www/`](www/).

Read these files before changing the portal:

1. [`README.md`](README.md) for installation and operator configuration.
2. [`doc/architecture.md`](doc/architecture.md) for component ownership and
   request flows.
3. [`doc/SharkTrust-Protocol.md`](doc/SharkTrust-Protocol.md) for the current
   device protocol.
4. [`doc/BACME-Protocol-Legacy.md`](doc/BACME-Protocol-Legacy.md) only when
   maintaining the two legacy endpoints.
5. If the local ignored development workspace is present, read
   `development/README.md` for conformance and portal smoke tests. The entire
   `development/` directory is intentionally absent from the public repository.

The ACME client shipped with Mako and Xedge has a different authoritative
source tree:

```text
C:\Users\wini\develop\WebServer\BAS-Resources
```

Do not release client code from `development/BAS-Resources`. That ignored,
nested checkout contains test fixtures and an older source snapshot. Its
source files are not the release authority.

## Working state on September 5, 2026

Before this documentation cleanup, the portal repository was clean at commit
`f4c691c`. The authoritative BAS-Resources checkout was on branch `ACME-V2` at
commit `389a26f` with uncommitted ACME, Mako, and Xedge changes. Preserve those
changes. Always run both status commands before editing:

```powershell
git status --short
git -C C:\Users\wini\develop\WebServer\BAS-Resources status --short
```

The test and production portals were both read-only checked on September 5,
2026. Both were active under `SharkTrustX.service`, had zero systemd restarts,
and returned HTTP 200 with successful TLS verification. Both deployed the same
packages:

| Package | SHA-256 |
| --- | --- |
| `/usr/local/bin/mako.zip` | `8e0a023f2f65087e25b1fb90e64613e6f2ee435fa153b899f3dd74fc08bdd52d` |
| `/opt/SharkTrustX/SharkTrustX.zip` | `5acbf85d6136d7aea6ce2837f128dbbc5db42b0936f1fc05fa819d5138cd7be2` |

This is a dated handover record, not a substitute for checking the current
service and package hashes before a deployment.

The corresponding verified deployment backups are:

```text
Test:       /opt/SharkTrustX/backups/deploy-20260904T162123Z
Production: /opt/SharkTrustX/backups/deploy-20260904T162458Z
```

## Implementation map

| Path | Responsibility |
| --- | --- |
| `www/.preload` | Composition root, configuration, BIND updates, routing, database integration, certificate startup, and unload handling. |
| `www/sharktrust.lsp` | Current JSON/HTTPS device endpoint. |
| `www/.lua/SharkTrust.lua` | Current protocol validation, authentication, enrollment, and commands. |
| `www/.lua/ZoneDB.lua` | Database access. One dedicated writer owns serialized writes. |
| `www/.lua/CreateDB.lua` | Database creation and schema migrations. Current schema version is 1.5. |
| `www/.lua/CertUpdater.lua` | Portal and zone certificate lifecycle. |
| `www/.lua/RevConnBridge.lua` | Reverse sockets and bounded browser-request queues. |
| `www/.lua/SensitiveAction.lua` | Session-bound verification for secret display, generated C download, and cleanup previews. |
| `www/.lua/www/` | Private browser templates, route handlers, and the light dashboard shell. |
| `www/assets/style.css` | Portal theme tokens and component rules. Start theme changes in its `:root` block. |
| `www/command.lsp`, `www/rtoken.lsp` | BACME 1.x compatibility endpoints. |

## Contracts that must remain true

- Load the portal as a root application with priority 1 or higher. Reverse
  WebSocket requests can otherwise be consumed by another root handler.
- Run the Linux portal as `root`. It writes BIND files under
  `/etc/bind/zones/` and calls `rndc`.
- Keep `mako.conf`, `zones.db`, ACME state, certificates, generated BIND data,
  credentials, and logs outside the application ZIP and out of Git.
- Keep all current device operations on HTTPS `/sharktrust.lsp`. Certificate
  validation must fail closed.
- Treat zone keys, zone secrets, request proofs, device credentials, Entra
  secrets, private keys, session identifiers, and reverse URLs as secrets.
  Never print or commit them.
- Preserve the exact JSON bytes used to calculate a SharkTrust request proof.
- Database writes must remain serialized by `ZoneDB.lua`. When an HTTP result
  depends on a write callback, convert the response with
  `response:deferred()` and finish it from the callback. Do not poll or sleep
  in a request handler.
- A device credential belongs to one device and one zone. Device removal must
  revoke it and remove its reverse-connection state.
- The inactive-device cleanup must use a server-generated preview, require
  acknowledgement, and remove only the previewed device set for the selected
  zone.
- Viewing the zone secret and downloading `tokengen.c` both require the
  email verification flow in `SensitiveAction.lua`.
- Keep the legacy endpoints only while older clients need them. New work must
  follow `doc/SharkTrust-Protocol.md`.

## Local validation

The local ignored `development/README.md` documents the independent Python
protocol client, concurrency check, credential-revocation check, database
migration fixture, generated C proof test, and browser portal smoke test.

Use an isolated Mako home and trusted HTTPS identity. A Windows run exercises
portal and protocol logic, but it simulates BIND commands and does not prove
public DNS, ACME issuance, SMTP delivery, or reverse connections.

After a documentation-only change, at minimum run:

```powershell
git diff --check
```

For portal code, run the affected test from `development/README.md` and inspect
Mako output for `SharkTrustX: Ready` and any Lua exception. An HTTP 200 alone
does not prove the intended handler ran.

## Build and deployment

The production Mako resource package must be built from the authoritative
BAS-Resources checkout:

```powershell
Push-Location C:\Users\wini\develop\WebServer\BAS-Resources\build
$env:MinifyMakoZip = "no"
cmd.exe /d /c "call mako.cmd"
Remove-Item Env:MinifyMakoZip
Pop-Location
Get-FileHash -Algorithm SHA256 `
  C:\Users\wini\develop\WebServer\BAS-Resources\build\mako.zip
```

Verify that the archive contains the current ACME files before upload. Recheck
the local, uploaded, and installed SHA-256 values rather than copying a hash
from this document.

The current Linux layout on both portals is:

| Path | Purpose |
| --- | --- |
| `/usr/local/bin/mako` | Mako executable. |
| `/usr/local/bin/mako.zip` | Mako resource package. |
| `/opt/SharkTrustX/mako.conf` | Host configuration and application loading. |
| `/opt/SharkTrustX/SharkTrustX.zip` | Portal application package. |
| `/opt/SharkTrustX/` | Working directory and writable portal state. |
| `/opt/SharkTrustX/backups/` | Timestamped deployment backups. |
| `/etc/systemd/system/SharkTrustX.service` | Root-owned systemd unit. |

The service runs:

```text
/usr/local/bin/mako -s
```

For a controlled foreground check, stop the service, run the same executable
from `/opt/SharkTrustX`, confirm `SharkTrustX: Ready`, stop the foreground
process, and start the service again. Never run the service and a foreground
portal against the same database and ports at the same time.

```bash
sudo systemctl stop SharkTrustX
cd /opt/SharkTrustX
sudo /usr/local/bin/mako -s
# Press Ctrl-C after the checks finish.
sudo systemctl start SharkTrustX
sudo systemctl is-active SharkTrustX
```

Deployment targets are:

```text
Test:       ssh iot.sharkssl.com
Production: ssh wini@sharktrustx.realtimelogic.com
```

Before replacement, back up the installed ZIP being changed. Do not replace
`mako.conf`, `zones.db`, ACME state, certificate state, or BIND data during a
code-only deployment. After replacement, check service state, restart count,
package hashes, HTTPS status, TLS verification, startup logs, authenticated
portal access, one existing device, and reverse access when that path changed.

## Completion record

At handover, report:

- changed files in both repositories;
- commits and uncommitted work preserved;
- package hashes actually installed;
- exact local tests and target runtime used;
- service, HTTPS, TLS, login, device, DNS, certificate, and reverse checks
  actually run;
- backup paths for any deployment; and
- every test that still requires the operator, public DNS, email, hardware, or
  a real certificate authority.

Do not describe a source review, deterministic fake transport, or HTTP health
check as complete production acceptance.
