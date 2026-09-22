# SharkTrustX

SharkTrust eXtended (SharkTrustX) is an extended version of [SharkTrust](https://github.com/RealTimeLogic/SharkTrust) that provides additional features such as remote access of private servers in addition to providing automatic SSL certificate management for Intranet web servers. Unlike SharkTrust, which works with any web server, SharkTrustX is designed exclusively for [Barracuda App Server](https://realtimelogic.com/products/barracuda-application-server/) powered products such as the [Mako Server](https://makoserver.net/).

See the [SharkTrustX product page](https://realtimelogic.com/products/SharkTrustX/) for additional information.

## SharkTrustX Portal and Mako Server License

The SharkTrustX Portal software is released under the MIT License and may be used, modified, and distributed free of charge in accordance with its terms.

The SharkTrustX Portal runs on the Mako Server, which is separately licensed commercial software. However, when a Mako Server instance is used exclusively to operate a SharkTrustX Portal, a no-cost Mako Server license is automatically granted for that use.

If the Mako Server is used for any purpose other than hosting the SharkTrustX Portal, a standard Mako Server license must be obtained.


## Domain Names


**NOTE:** The following domain names are used in the instructions below. Replace these names with your own such as xx.company.com.

* **Name server 1:** acme1.realtimelogic.com
* **Name server 2:** acme2.realtimelogic.com
* **Service's domain name:** acme.realtimelogic.com

The software requires two name servers listed in the configuration file. However, the software is currently limited to running on one VPS and the DNS A record for the three fields above must all point to the same VPS.

## Tutorials

* [Installing the SharkTrustX Portal](https://realtimelogic.com/articles/Installing-the-SharkTrustX-Portal)
* [SharkTrustX Zone Management](https://realtimelogic.com/articles/SharkTrustX-Zone-Management)

## Device Protocol Documentation

- [`doc/SharkTrust-Protocol.md`](doc/SharkTrust-Protocol.md) is the canonical
  specification for the SharkTrust device-to-portal protocol.
- [`doc/BACME-Protocol-Legacy.md`](doc/BACME-Protocol-Legacy.md) documents the legacy
  header and refresh-token protocol used by older clients.
- [`doc/architecture.md`](doc/architecture.md) explains portal components,
  request flows, persistent state, and security boundaries.
- [`AGENTS.md`](AGENTS.md) is the maintainer and session-handover guide.

## Microsoft Entra SSO

Microsoft Entra SSO is configured independently for each zone by that zone's
administrator. In a customer deployment, this is the person responsible for
the customer's Entra tenant and app registration, not the product engineer who
built the BAS-powered product.

The zone's **Settings** page shows the exact redirect URI to add to the Entra
app registration. Enter the tenant ID, client ID, client secret **Value**, and
the secret's expiration date. The expiration date enables advance email
notifications to the zone owner using the Mako Server SMTP configuration.

If Microsoft rejects an invalid or expired secret during login, the portal
displays a credential-recovery form. The replacement secret is verified by a
new Microsoft sign-in before it is saved for the zone.

While Microsoft sign-in initializes, the portal displays a temporary status
and a retry link. SSO settings require an HTTPS redirect URI, except for
localhost testing. If Entra reports error `700025`, check that the app
registration uses a **Web** redirect URI and the appropriate public-client
settings; replacing the client secret does not resolve that configuration error.

A verified replacement becomes active in memory immediately. Its database
write completes asynchronously, and the portal reports whether it was saved.
If saving fails, login can still succeed, but the replacement will not survive
a restart. Automatic user registration completes its database write before
the browser is allowed to finish logging in.

## Portal Email Messages and Required Actions

Portal email can report a failed request even while other devices, existing
sessions, and certificates continue working. Check the zone, device name,
timestamp, and message text before treating an email as a portal-wide outage.
An automatic retry means the operation will be tried again; it does not mean
the underlying problem will necessarily correct itself.

When Mako runs as a service, ordinary `SharkTrustX:` log entries are buffered
for delivery to `log.smtp.to`. They have a server-local `HH:MM:` timestamp.
An error flushes the pending buffer immediately with the subject
`SharkTrustX Error`, including earlier informational entries. Otherwise,
Mako sends the buffer when its configured delay or size limit is reached.
Foreground runs print these portal log messages to the console instead.

Client-related portal diagnostics use the same address suffix in the console,
buffered log emails, and separate enrollment-conflict or sign-in notices:
`[device IP=192.168.1.50; WAN IP=203.0.113.20]`.

- **Device IP** is the valid IPv4 address reported by the authenticated device,
  or its last registered local address when the request has no new address.
  The stored address can be stale. Before device authentication, or when no
  valid local address is available, the value is `unknown`.
- **WAN IP** is the connection peer observed by the portal, including IPv6
  when applicable. Behind a proxy, this identifies the proxy. The portal does
  not substitute a forwarded HTTP header for this address.
- Browser administration and Microsoft sign-in diagnostics use
  `device IP=unknown`: an ordinary browser request does not disclose the
  browser computer's private address. Its observed WAN IP is still included.

Deferred writes, email delivery failures, and device DNS cleanup retain the
addresses of the initiating request. Background certificate maintenance,
provider refreshes, scheduled credential-expiration notices, and low-level
database or Mako runtime traces have no associated client address context.
Rejected HTTP requests do not each generate a new email; the existing
notification triggers and batching rules still apply.

### Enrollment Name Conflicts

`Enrollment name conflict in zone local.makoserver.net for test` means an
authenticated enrollment requested the exact name
`test.local.makoserver.net`, which another registration already owns. The
request did not recover that registration using its saved device credential.
The portal returns `name_unavailable` and leaves the existing device unchanged.
`test1.local.makoserver.net` is a different name and may work normally.

Common situations include a reset or lost device state, a second device using
the same requested name, or switching away from a portal and later returning
without its previous registration. Each authenticated exact-name conflict
also triggers an immediate email with subject
`SharkTrustX enrollment name conflict` to `log.smtp.to`. Its diagnostic body
compares the requested device's addresses and descriptive information with
the existing device's registration and last-access information. It does not
include device credentials or request proofs.

**Action required if enrollment is still failing:** identify the requesting
device and compare it with the existing portal entry. Restore that device's
own saved registration if available, choose an unused name, or use
`namePolicy="increment"` if a numbered name is acceptable. Remove an existing
entry only after confirming it is obsolete; a working registration must not
be deleted merely to silence an alert. Stop any obsolete test instance that
continues requesting the name.

The current Mako/Xedge client retries an exact-name conflict hourly while its
runtime remains open. Retrying alone cannot free an occupied name. Restarting
the client can initiate an earlier attempt, and older clients can use different
retry intervals. If these were completed tests and no client is still failing,
no corrective change is needed. Successful recovery with the same saved
credential does not produce a conflict email.

### Microsoft Entra Sign-in Diagnostics

These log messages are prefixed `SSO <zone>:` and go to the portal log recipient.
They describe a particular sign-in attempt or that zone's SSO provider, not
device enrollment or ACME certificate issuance.

| Message | Meaning and recovery | Required action |
| --- | --- | --- |
| `ID token validation failed: Invalid ID token issuer` | The returned token's version was not `2.0`, or its issuer did not exactly match the issuer in the configured provider metadata. That sign-in was rejected; existing sessions are unaffected. This is not the expired-client-secret diagnostic. There is no automatic repair of the rejected login. | Start a fresh sign-in. If it succeeds and the error does not recur, no configuration change is needed. If it repeats, the zone administrator should check the configured tenant ID and app registration, and compare the expected issuer with the failing identity flow. Do not disable issuer validation. The email alone does not identify the account or explain the mismatch. |
| Other `ID token validation failed: ...` messages | Header, signature, tenant, audience, nonce, validity time, or object-ID validation failed. Unknown signing keys trigger a key refresh during validation, but a rejected login is not automatically replayed. | Retry a fresh login once. For repeated failures, inspect the stated check: verify the tenant and client ID, check the server clock for time errors, and investigate signing-key/network failures. Preserve token validation; do not put raw tokens in diagnostic emails. |
| `Microsoft sign-in returned: ...` | Microsoft returned an error, which can include a cancelled or denied sign-in. No session is created by that attempt. | No portal repair is needed for an intentional cancellation. Otherwise use the returned error to resolve account access or app configuration, then sign in again. |
| `Token exchange failed: status=... error=... code=...` | The authorization-code exchange failed. Codes `7000215` and `7000222` trigger the secret-recovery flow; `700025` is an app configuration issue. A temporary HTTP failure can clear, but the login must be started again. | For an invalid or expired secret, supply a valid replacement through the recovery form or zone Settings. For `700025`, check the Web redirect URI and public-client settings as described above. For other errors, investigate the supplied status and code. |
| `Cannot refresh OpenID provider data: ...` | Metadata or signing-key refresh failed. The timer tries again after about one minute; after success, regular refresh is daily. Previously loaded data may still allow sign-in. | Brief network failures can recover automatically. If repeated, check outbound HTTPS, DNS, trust certificates, the clock, and the configured tenant. |
| `Cannot initialize SSO for ...` | The provider could not be constructed, for example because required settings are missing or invalid. This differs from a network refresh failure after initialization. | Correct the zone's SSO settings. A later initialization attempt can succeed after correction; repeated attempts do not fix invalid configuration. |
| `Cannot persist SSO defaults for ...` | The database did not save initialized SSO defaults. Current in-memory settings may still work. | Check database permissions, free space, and write errors, then save the settings again. Do not rely on a restart to retain unsaved values. |
| `Credential persistence callback failed: ...` | A replacement secret passed sign-in validation but could not be saved. Login can succeed with the in-memory replacement. | Repair the database write problem and save the valid secret and expiration date before restarting. See `credential-update-failed` below. |
| `Notification callback failed: ...` | The SSO notification handler raised an error. The notification is not automatically queued for redelivery. | Inspect the exception and notification/email configuration. Check the underlying credential condition even if no separate notice arrived. |

### Microsoft Entra Credential Notices

The zone owner receives a separate email with subject
`Microsoft Entra credential: <kind>`. Its text is also recorded in the portal
log. Expiration reminders use the expiration date saved in zone Settings; they
do not query Microsoft for that date. The default reminder thresholds are
60, 30, 14, 7, and 1 day before expiration. Checks run with provider refreshes.
Notification suppression is held in memory, so restarting the portal or
recreating a provider can repeat a notice.

| Subject suffix | Automatic behavior | Required action |
| --- | --- | --- |
| `credential-expiring` | Reminder only. The portal does not generate or rotate an Entra secret automatically. | The zone administrator should obtain and save a replacement before expiration. |
| `credential-expired` | The saved expiration date has passed, or Microsoft reported code `7000222`. A wrong saved date can produce a warning while login still works. | Check the actual secret and its saved date. Replace an expired secret, or correct an inaccurate date. |
| `credential-invalid` | Microsoft rejected the configured secret with code `7000215`; a recovery form is offered for that login. | Supply the correct secret **Value**, not its identifier. Repeating the unchanged configuration will not correct it. |
| `credential-updated` | The replacement was verified by sign-in and its save callback reported success. | No action is required if the replacement was expected. Investigate an unexpected change. |
| `credential-update-failed` | The replacement works in memory but was not persisted. It may be lost on restart. | Repair storage and save the replacement again; this needs action even when login currently works. |

### Certificates, DNS, Storage, and Audit Messages

These entries may be included in a buffered log email or an immediate error
email. Certificate messages concern certificates served by the portal;
device-side `ACME event` messages are a separate client log.

| Message or message group | Automatic behavior and required action |
| --- | --- |
| `Certificate request error '<name>': ...` and `Retrying regular/wildcard certificate ...` | Certificate requests retry after 60, 300, 900, 3,600, then 21,600 seconds, continuing at the last interval. Existing certificates can keep HTTPS working until expiration. A temporary CA/network failure may clear automatically. Repeated errors require checking the reported cause, DNS delegation/TXT publication, and public port 80 for HTTP-01 names. Do not wait for expiry to investigate. |
| `Creating certificate ...`, `Updating certificate ...`, `Creating RSA private key` | Normal certificate provisioning activity. No action is required unless followed by an error. |
| `Cert ... not found`, `Warn: no certificates to load!` | The selected certificate profile has no file to load. Initial issuance can resolve this automatically. If it persists or HTTPS lacks the expected certificate, inspect issuance errors and the writable `acmecert/` directory. |
| `UTCTime parse error for ...` | A stored certificate's expiration could not be parsed. The updater treats it as due for replacement. Check the certificate file and subsequent issuance results; replacement may recover it, but repeated parse errors need investigation. |
| `Creating shark-cert failed: ...` | Installing the available certificate set into the HTTPS listener failed. This is not proof that certificate issuance failed. There is no dedicated installation retry loop. Inspect the error, certificate/key compatibility, and subsequent installation results; successful HTTPS with an older certificate does not establish recovery. |
| `Command ... failed: ...`, `Device DNS refresh failed for zone ...`, `Inactive-device DNS refresh failed for zone ...`, `BACME DNS refresh failed for zone ...`, `Reverse-connection DNS refresh failed for zone ...`, `SharkTrust timed DNS cleanup failed` | A system/BIND command or DNS refresh failed. There is no dedicated retry queue for these failed changes. Check BIND configuration, permissions, and `rndc`, then repeat the affected refresh and verify DNS. A committed database change can exist even when DNS has not been updated. |
| `No ZoneT for ...`, `Terminating zone warn: cannot find ...` | The requested zone was not available to the operation. Check whether it was removed or renamed and inspect the operation's result. No automatic repair is promised. |
| `Settings database write failed ...`, `Inactive-device preview failed ...`, `Inactive-device removal failed ...` | A storage operation failed; the portal does not automatically repeat that administrative action. Check storage and the response shown in the browser. For cleanup, obtain a new preview before trying removal again. |
| `Settings post-commit action failed ...`, `SharkTrust post-commit action failed ...`, `SharkTrust completion action failed ...`, `SharkTrust response creation failed` | A follow-up action or response failed, possibly after the database change committed. Inspect current device/settings state and DNS before repeating a change. Do not assume an error means nothing was saved. No general automatic replay is provided. |
| `SharkTrust internal request failure`, `parsing ... failed`, Lua tracebacks, `Lua Err: ...`, `LSP Err: ...` | An internal or template/runtime error needs investigation if it recurs. Preserve the traceback and request context, excluding secrets. Automatic recovery depends on the failed operation; an email is not a recovery confirmation. Mako's generic Lua/LSP exception emails require `log.logerr=true`. |
| `Ready ...`, `New zone ...`, `Portal ACME disabled for Windows test` | Informational startup/configuration messages. `Ready` does not prove that DNS or certificate issuance has completed. The ACME-disabled message is expected only in the Windows test configuration. |
| `Updated setting ...`, `Sent verification request ...`, `Verified request ...`, `Generated tokengen.c ...`, `Previewed ... inactive devices ...`, `Removed ... inactive devices ...`, `Password reset request for zone ...` | Audit records for user actions, not failures needing automatic correction. No action is required when expected. If unexpected, review the named user, source address, and affected zone. A preview does not mean devices were removed. |

### Account, Verification, and Email-delivery Messages

These are separate transactional emails. They are sent to the address shown
below rather than necessarily to the portal log recipient.

| Subject | Recipient and required action |
| --- | --- |
| `DNS Service E-Mail Validation` | The submitted zone-registration email address. Follow the validation instructions to continue the requested zone setup; it will not complete merely by waiting. Ignore an unrequested validation. |
| `DNS Service Account Information: <zone>` | The zone registrant after setup. Retain the zone key securely and follow the setup information. This is a completion notice, not an error; DNS availability can lag while delegation propagates. |
| `Create account for <zone>` | A user registering in a zone that permits self-registration. Paste the supplied registration data into the form to complete the process. |
| `<name> : <email> requests access to <zone>` | The zone administrator when approval is required; the name can be `Single Sign On`. Review the request and approve only authorized users. It does not approve itself. |
| `Account accepted for <zone>` | The approved user. The account is ready for login; no repair is required. |
| `Password reset request for <zone>` | The affected user's or administrator's email address. Complete the reset only if requested; receiving the email alone does not change the password. An unrequested reset may be discarded. |
| `Secure two-step verification notification for <zone>` | The zone owner, after a request to view the zone secret or download `tokengen.c`. Enter the code in the initiating session within ten minutes. If unrequested, do not share the code; review the account and security settings. Expiration does not authorize the action. |
| An administrator-specified subject | The recipient selected on the administration **Send E-Mail** page. This is a manual message or SMTP test, not an automatic incident notice. |

`Enrollment conflict email delivery failed`, `SSO notification email failed`,
and `Verification email delivery failed` mean that a separate notification
could not be sent. Mako can also print `sendmail failed: ...` to the server
trace. Check SMTP connectivity, authentication, and delivery configuration,
using the administration email test. The send operation has no automatic
redelivery queue; a later repeated event may send another notice, but that is
not delivery of the lost message. If SMTP itself is broken, its error email
may also be undeliverable, so inspect the local service log. Retry the requested
verification or account action after correcting delivery.

Message handling is implemented in [portal startup](www/.preload),
[shared client diagnostics](www/.lua/ClientLog.lua),
[device enrollment](www/.lua/SharkTrust.lua),
[certificate maintenance](www/.lua/CertUpdater.lua),
[Microsoft sign-in](www/.lua/ms-sso.lua), and the
[browser action handlers](www/.lua/www/).

## Customizing SharkTrustX

1. Fork or clone this repository.
2. Customize the framework-free light dashboard in [the shared template](www/.lua/www/template.lsp) and [its stylesheet](www/assets/style.css). The responsive shell is based on the custom variant in the [Light Dashboard example](https://github.com/RealTimeLogic/LSP-Examples/tree/master/Light-Dashboard). All theme colors, sizing, radii, and navigation width are CSS custom properties in the documented `:root` block at the top of the stylesheet, so branding changes do not require editing component rules. The default palette follows Real Time Logic's restrained technical theme: dark neutral surfaces, green primary actions, and yellow links. See the Mako Server tutorial [How to Build an Interactive Dashboard App](https://makoserver.net/articles/How-to-Build-an-Interactive-Dashboard-App) for details.


## Installation Instructions

**1:** Sign up for a VPS provider and install a Debian (derivative) distribution.

**2:** After signing up for a VPS Service, take note of the online server's IP address, navigate to your company's DNS settings page, and add A text records for xx1.company.com, xx2.company.com, and xx.company.com, where xx is a sub domain such as 'acme' and company.com is your company name or any other domain name you own. All A records must point to the VPS IP address.

**3:** Wait 24 hours for the DNS settings to take effect.

## Automatic Installation

Use the [SharkTrustX Ansible Installation Scripts](https://github.com/RealTimeLogic/SharkTrustXInstaller)

## Manual Installation

**4:** Login to the online VPS using SSH, and run the following set of commands in the SSH shell:

### Update Linux
```console
apt-get update
apt-get -y upgrade
```

### Install Required Applications
```console
apt-get -y install bind9 whois lsof git nano
```

### Clone GIT repo in a suitable directory
```console
git clone https://github.com/RealTimeLogic/SharkTrustX.git
```

### Configure the Mako Server

SharkTrustX is a web application powered by the Mako Server.

Create a mako.conf script and add instructions for loading SharkTrustX

```lua
apps = {
   { name='', prio=1, path='SharkTrustEx/www'},
}
```

> [!IMPORTANT]
> SharkTrustX must be loaded as a root application with priority 1 or higher.
> The priority lets SharkTrustX receive reverse-connection requests before
> Mako's built-in resources. Without it, built-in endpoints can intercept
> requests such as TraceLogger WebSocket connections, which can cause an
> unexpected authentication prompt followed by `503 Service Unavailable`.

Add the following to mako.conf:


```lua
-- The following settings are used by the Lua code in /home/mako/www
settings={
   ns1="acme1.realtimelogic.com",
   ns2="acme2.realtimelogic.com",
   dn="acme.realtimelogic.com",
   acme={
      production=true,
      -- ECC certificate keys use the Mako TPM by default. Set rsa=true to
      -- create and use a software RSA certificate key instead.
      rsa=false,
      -- Optional additional public names served by this portal. The portal
      -- name in settings.dn is always included automatically.
      domains={"iot.company.com"}
   }
}

-- Required and used by /home/mako/www/.preload
log={
   logerr = true, -- Send Lua LSP exceptions by email
   smtp={
      subject="ACME Log",
      -- See the documentation for the required smtp fields
      -- https://realtimelogic.com/ba/doc/en/Mako.html#oplog
   }
}
```

Set `settings.acme.production=false` while validating a deployment against the
Let's Encrypt staging service. SharkTrustX keeps staging account and
certificate files under `acmecert/` with a `staging.` filename prefix. The
unprefixed production account and certificates remain available, so changing
the setting regenerates and loads the selected profile without overwriting the
other profile. The certificate private key is shared by both profiles.

SharkTrustX always keeps its ACME account key as an ECC key in the Mako TPM.
Certificate keys are also ECC and TPM-backed by default. Setting
`settings.acme.rsa=true` selects a software RSA certificate key instead. The
Mako TPM interface supports ECC keys only and is therefore never used for RSA
key generation. The selection applies when the certificate key is first
created; an existing key is reused.

Names in `settings.acme.domains` use HTTP-01 and must have public A records
pointing to the portal, with TCP port 80 reachable from the certificate
authority. Configure additional portal names here rather than enabling Mako's
separate top-level `acme` table: SharkTrustX must install the static, zone, and
wildcard certificates together so one certificate manager owns the HTTPS
listener.

Save the changes and start the Mako Server as user `root`. If `mako.conf` loads
the application with `prio=1` as shown above, start Mako normally:

```console
mako
```

When loading a deployed `SharkTrustX` application directly from the command
line, specify the same priority explicitly:

```console
mako -l:1:SharkTrustX
```

Load the application by one method only. Do not load it from both `mako.conf`
and the command line.

You should see the following being printed in the console two minutes after starting the Mako Server.

```console
ACME: acme.realtimelogic.com renewed
```
The printout should be for your own service's domain name. The above printout signals that the service is operational. You may now terminate the Mako Server process by using CTRL-C and then [install the Mako Server as a service](https://makoserver.net/articles/Installing-Mako-Server-as-a-Service-on-Linux).

You may now use a browser and navigate to xx.company.com (e.g. acme.realtimelogic.com)
