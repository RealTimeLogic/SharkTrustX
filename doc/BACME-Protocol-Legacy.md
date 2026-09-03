# BACME 1.x Protocol Specification

This document describes the legacy BACME 1.x protocol retained for older
clients. New clients use the current protocol specified in
[`SharkTrust-Protocol.md`](SharkTrust-Protocol.md).

## 1. Introduction

The Barracuda Automatic Certificate Management Environment (BACME) protocol
lets a private-network web server register a DNS name, update its address, and
create the DNS TXT record required by an Automatic Certificate Management
Environment (ACME) DNS-01 challenge.

## 2. Terms

- **ACME**: Automatic Certificate Management Environment, specified by RFC
  8555.
- **BACME**: The device-to-SharkTrustX protocol specified here.
- **Zone**: A DNS zone registered in SharkTrustX.
- **Zone key**: A zone-wide credential used by every BACME 1.x client in the
  zone.
- **Zone secret**: A second zone-wide secret used to derive the calculated
  request token.
- **Device key**: The identifier returned when a device is registered.
- **Refresh token**: A short-lived, in-memory server value used when calculating
  request tokens.

## 3. Transport and endpoints

BACME 1.x uses two HTTPS endpoints:

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/rtoken.lsp` | `HEAD` | Obtain or refresh the server refresh token. |
| `/command.lsp` | `GET` | Send a BACME command using HTTP request headers. |

All protocol data is carried in HTTP headers. Normal responses have no body.
The server rejects a `/command.lsp` request that is not received over TLS.
Clients must validate the portal certificate and host name because the zone
credentials and calculated request tokens provide no protection against an
active TLS attacker.

## 4. Credential formats

| Value | Current format |
| --- | --- |
| Zone key | 32 random bytes encoded as 64 hexadecimal characters. |
| Zone secret | 32 random bytes encoded as 64 hexadecimal characters. |
| Device key | 10 random bytes encoded as 20 hexadecimal characters. |
| Refresh token | 32 random bytes encoded with base64url in the HTTP header. |
| Request hash | 32 random bytes encoded with base64url in `X-Hash`. |
| Calculated token | 32-byte SHA-256 result encoded with base64url in `X-Token`. |

The zone key and zone secret are shared by all BACME 1.x devices registered in
the zone. The device key identifies one registered device, but it is not a
separate cryptographic authenticator.

The portal can generate a C module that embeds and obfuscates the zone secret.
This makes direct extraction from a device image more difficult. The generated
C module is an optional client-side hardening measure. It does not change the
wire protocol or remove the shared zone credentials.

## 5. Refresh-token exchange

The client first sends:

```http
HEAD /rtoken.lsp HTTP/1.1
X-Key: <64-hex-character-zone-key>
X-Dev: <optional-20-hex-character-device-key>
```

`X-Key` is required. `X-Dev` is optional. If the supplied device key exists,
the current implementation uses the request to update that device's observed
WAN address and last-access time.

A successful request returns HTTP `200 OK` with these headers:

| Header | Meaning |
| --- | --- |
| `X-RefreshToken` | Base64url-encoded 32-byte refresh token. |
| `X-Expires` | Advertised token expiration as a BAS date-time string. |
| `X-Date` | Current server time as a BAS date-time string. |
| `X-ExpIn` | Seconds between `X-Date` and `X-Expires`. |

An invalid zone key or a method other than `HEAD` returns HTTP `404 Not Found`.

Refresh tokens exist only in portal process memory. A portal restart
invalidates them. The current implementation may reuse one process-wide token
for multiple clients and zones. A newly created token advertises an expiration
about 10 hours and 15 minutes after creation. The server stops selecting it for
new refresh responses when 15 minutes or less remain, and removes it from the
valid-token table 11 hours after creation. Clients must obey `X-Expires` and
request a replacement before that time.

## 6. Command authentication

Every request to `/command.lsp`, including `Register` and `GetWan`, includes
all of these headers:

| Header | Meaning |
| --- | --- |
| `X-Command` | Case-sensitive command name. |
| `X-Key` | 64-hex-character zone key. |
| `X-RefreshToken` | Base64url refresh token obtained from `/rtoken.lsp`. |
| `X-Hash` | Base64url encoding of a new 32-byte random value. |
| `X-Token` | Base64url encoding of the calculated SHA-256 token. |

Commands that act on a registered device also include `X-Dev` as described in
Section 8.

### 6.1 Derived key

The client and server derive a 32-byte key as follows:

```text
zoneKeyBytes = hexDecode(zoneKey)
derivedKey = PBKDF2-HMAC-SHA256(
    password = upperCase(zoneSecret),
    salt = zoneKeyBytes,
    iterations = 1000,
    outputLength = 32)
```

The generated C module calculates the same value without exposing the zone
secret through its Lua interface.

### 6.2 Per-request token

For each command, the client creates a new 32-byte random value named `hash`
and calculates:

```text
token = SHA256(hash || derivedKey || serverIpText || refreshToken)
```

`serverIpText` is the textual peer IP address observed when the client obtains
the refresh token. `refreshToken` and `hash` are their decoded binary values.
The `||` operator means byte concatenation.

The command name and command-specific headers are not included in this digest.
The server does not keep a replay cache for `X-Hash`. Validated HTTPS is
therefore required, and a client must generate a fresh random `X-Hash` for each
request.

## 7. Common responses

All ordinary commands return HTTP `201 Created` on success and have no response
body. `RevCon` returns HTTP `202 Accepted` and transfers the connection to the
reverse-connection bridge.

| Status | Current meaning |
| --- | --- |
| `201 Created` | The command was accepted. |
| `202 Accepted` | The `RevCon` socket was accepted by the bridge. |
| `400 Bad Request` | TLS is missing, a command is unknown, or a required command field is missing or invalid. |
| `403 Forbidden` | The refresh token or calculated token is invalid. |
| `404 Not Found` | Authentication headers are missing, the zone key is invalid, or a device key is unknown. |
| `500 Internal Server Error` | The portal encountered an unexpected error. |

When the request reached the BACME error handler, an error response includes
`X-Reason`. A request that is rejected as unrelated traffic may receive a plain
`404` without `X-Reason`.

## 8. Commands

The tables below list command-specific headers. Every request also includes the
five authentication headers from Section 6.

### 8.1 Register

Registers a new device in the zone selected by `X-Key`.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `Register` |
| `X-IpAddress` | Yes | Device IPv4 address in dotted-decimal form. |
| `X-Name` | No | Requested DNS label or full name in the selected zone. Defaults to `device`. |
| `X-Info` | No | Device description stored by the portal. |
| `X-Dns` | No | `local`, `wan`, or `both`. Any other or missing value selects `local`. |

The DNS label may contain letters, digits, and hyphens, but it cannot start or
end with a hyphen. The portal lowercases the name and appends a number when the
requested name is already in use.

Success headers:

| Header | Meaning |
| --- | --- |
| `X-Dev` | Assigned 20-hex-character device key. |
| `X-Name` | Assigned full DNS name. |

The BACME 1.x handler queues the database write and returns the generated
device key without waiting for the asynchronous write callback.

### 8.2 IsRegistered

Checks whether a stored device key still identifies a device. The portal also
updates the observed WAN address when it changed.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `IsRegistered` |
| `X-Dev` | Yes | Device key returned by `Register`. |

Success returns the assigned full DNS name in `X-Name`.

### 8.3 IsAvailable

Checks whether a requested device name is available in the selected zone.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `IsAvailable` |
| `X-Name` | No | DNS label or full name in the selected zone. Defaults to `device`. |

Success returns `X-Available: yes` when the name is available and
`X-Available: no` when it is already in use.

### 8.4 SetIpAddress

Updates the device's local address, the portal-observed WAN address, and the
DNS address-selection mode.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `SetIpAddress` |
| `X-Dev` | Yes | Registered device key. |
| `X-IpAddress` | Yes | Device IPv4 address in dotted-decimal form. |
| `X-Dns` | No | `local`, `wan`, or `both`. Any other or missing value selects `local`. |

Success returns the assigned full DNS name in `X-Name`.

### 8.5 SetAcmeRecord

Adds or replaces a temporary DNS TXT record for the device's ACME DNS-01
challenge.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `SetAcmeRecord` |
| `X-Dev` | Yes | Registered device key. |
| `X-RecordName` | Yes | DNS record name requested by the ACME client. |
| `X-RecordData` | Yes | DNS TXT value calculated by the ACME client. |
| `X-DnsResolveTmo` | No | DNS wait time in milliseconds. Defaults to `120000`. |

The portal rebuilds the zone data and schedules automatic removal after
`X-DnsResolveTmo` plus 10 seconds. Success has no command-specific response
headers.

### 8.6 RemoveAcmeRecord

Removes the temporary ACME records associated with the device and rebuilds the
zone data.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `RemoveAcmeRecord` |
| `X-Dev` | Yes | Registered device key. |

Success has no command-specific response headers.

### 8.7 GetWan

Returns the IPv4 peer address observed by the portal.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `GetWan` |

`X-Dev` is not required, but all five authentication headers in Section 6 are
required. Success returns the public peer address in `X-IpAddress`.

### 8.8 RevCon

Opens a reverse connection from a registered device to the portal.

Request headers:

| Header | Required | Meaning |
| --- | --- | --- |
| `X-Command` | Yes | `RevCon` |
| `X-Dev` | Yes | Registered device key. |

After authentication, the portal returns HTTP `202 Accepted`, takes ownership
of the request socket, and passes it to the reverse-connection bridge. This is
not an ordinary request-response command.

## 9. Current BACME 1.x security boundaries

The current implementation has these properties. They are relevant when
maintaining a BACME 1.x client or deciding whether to use SharkTrust:

- The zone key and zone secret are shared by every BACME 1.x device in a zone.
- Zone-key creation checks for an existing key across all zones. Zone-secret
  creation has no corresponding pre-check or database uniqueness constraint.
- The zone key is present in both refresh-token requests and every command.
- A refresh token is process-wide and is not bound to one zone or device.
- `X-Dev` identifies a device but does not provide independent authentication.
- The calculated token does not bind the command name or command-specific
  headers.
- The server does not reject replayed `X-Hash` and `X-Token` pairs while their
  refresh token remains valid.
- The current device lookup uses the globally unique device key and does not
  verify that the device row belongs to the zone authenticated by `X-Key`.
- Portal restart invalidates refresh tokens, but zone and device records remain
  in the database.

The current SharkTrust protocol removes the refresh-token exchange. See
[`SharkTrust-Protocol.md`](SharkTrust-Protocol.md).
