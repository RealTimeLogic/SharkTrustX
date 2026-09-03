# SharkTrust Protocol

## 1. Introduction

The SharkTrust protocol connects a private Barracuda App Server device to a
SharkTrustX portal. It lets the device register a DNS name, update its address,
publish the temporary DNS TXT record required by an Automatic Certificate
Management Environment (ACME) DNS-01 challenge, and establish a reverse
connection through the portal.

This document is the specification for the device-to-portal API.
Client and portal implementations must follow the request formats,
authentication rules, and responses defined here.

## 2. Transport and endpoint

### 2.1 HTTPS requirements

- Every request MUST use HTTPS.
- The client MUST validate the portal certificate chain, expiration, and host
  name.
- The client MUST fail closed when its clock or trust store cannot validate the
  portal certificate.
- A client MUST NOT send a zone key, device credential, or request proof over
  plain HTTP.
- Requests and responses use UTF-8 JSON unless this specification states
  otherwise.

The portal does not redirect an API request from HTTP to HTTPS. It rejects the
request so credentials are never forwarded after an insecure request.

### 2.2 Endpoint

All operations use `/sharktrust.lsp`.

Enrollment and device commands use JSON in `POST` requests. A reverse
connection uses `GET` without a request body.

### 2.3 Request limits

- A `POST` request's `Content-Type` MUST be `application/json`. A `charset`
  parameter is allowed.
- A request body MUST NOT exceed 4096 bytes.
- Unknown JSON members MAY be ignored unless they conflict with a required
  member.
- A JSON member defined as a string MUST satisfy the limits specified for that
  member after JSON decoding.

## 3. Authentication

### 3.1 Zone key

The zone key is a 64-character hexadecimal credential created with a
SharkTrustX zone. It authorizes `IsAvailable` and `Register` for that zone. A
client uses it only before the device has enrolled.

The client sends the zone key as:

```http
X-SharkTrust-Zone-Key: <64-hexadecimal-characters>
```

### 3.2 Zone secret and request proof

Each zone has a separate 32-byte random secret represented as 64 hexadecimal
characters. The secret MUST NOT be sent to the portal in an HTTP request. The
client derives a 32-byte proof key as follows:

```text
proofKey = PBKDF2-HMAC-SHA-256(
   password = uppercase ASCII zone-secret characters,
   salt = 32 bytes obtained by hexadecimal-decoding the zone key,
   iterations = 1000,
   outputLength = 32 bytes
)
```

The iteration count is not a password-strength control. The zone secret is
random and has 256 bits of entropy.

For `Register`, the proof message is:

```text
ASCII("SHARKTRUST-REGISTER") || NUL || ASCII(lowercase-zone-key) || NUL || request-body
```

For `IsAvailable`, the proof message is:

```text
ASCII("SHARKTRUST-AVAILABLE") || NUL || ASCII(lowercase-zone-key) || NUL || request-body
```

For an enrolled-device command, the proof message is:

```text
ASCII("SHARKTRUST-DEVICE") || NUL || ASCII(lowercase-device-credential) || NUL || request-body
```

For `POST`, `request-body` is the exact UTF-8 JSON byte sequence sent in the
HTTP request. The client MUST calculate the proof after JSON encoding and MUST
send the same bytes without re-encoding them. For a reverse-connection `GET`,
`request-body` is empty.

The `X-SharkTrust-Proof` header is the unpadded base64url encoding of:

```text
HMAC-SHA-256(proofKey, proof-message)
```

The encoded value is 43 characters. The portal MUST compare the supplied and
expected values in constant time. A missing or invalid proof receives the same
generic `invalid_credentials` response as any other authentication failure.

### 3.3 Device credential

The portal creates 32 random bytes for each enrolled device and returns the
value as 64 lowercase hexadecimal characters. The client treats the value as
an opaque credential and stores it as securely as the target permits.

Each accepted credential MUST be unique across all devices and zones. The
portal enforces this with a database-wide unique index on the stored credential
verifier. A collision makes the database write fail.

The client sends the credential as:

```http
Authorization: Bearer <64-lowercase-hexadecimal-characters>
```

The portal stores a verifier rather than the credential. It never returns an
existing credential. A credential remains valid across portal restarts until
its device is removed.

A device credential has no server-enforced maximum age. The portal does not
expire it solely because time has passed. This permits a device that has been
powered off for a long time to authenticate with its stored credential when it
returns. The recorded creation time is audit metadata, not an expiration time.

### 3.4 Credential exposure

Zone keys, zone secrets, request proofs, and device credentials MUST NOT appear
in URLs, logs, traces, screenshots, error messages, or committed test
configuration. Responses containing a newly created credential MUST use
`Cache-Control: no-store`.

## 4. JSON responses

A successful response is a JSON object containing `result`:

```json
{
  "result": {}
}
```

An error response is a JSON object containing `error`:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "The request is not valid."
  }
}
```

The `code` value is stable protocol data. The `message` is diagnostic text and
MUST NOT contain credentials or sensitive server state.

## 5. HTTP status codes

| Status | Meaning |
| --- | --- |
| `200 OK` | A device or availability command completed. |
| `201 Created` | Enrollment created a device and credential. |
| `202 Accepted` | A reverse connection was authenticated and transferred to the bridge. |
| `400 Bad Request` | JSON, a field, a command, or the transport is invalid. |
| `401 Unauthorized` | Authentication is missing or invalid. |
| `403 Forbidden` | The peer exceeded the authentication-failure limit. |
| `405 Method Not Allowed` | The endpoint does not support the HTTP method. |
| `409 Conflict` | An explicit device name is unavailable. |
| `413 Content Too Large` | The JSON body exceeds 4096 bytes. |
| `415 Unsupported Media Type` | The request is not JSON. |
| `500 Internal Server Error` | The portal could not complete the request. |
| `503 Service Unavailable` | A serialized database write or reverse-connection request could not complete. |

An authentication response MUST use the generic `invalid_credentials` error.
It MUST NOT reveal whether a supplied zone key or device credential exists.

## 6. Name availability and enrollment

### 6.1 Name availability

`IsAvailable` lets a client check an explicit name before displaying or
submitting an enrollment form. The device does not yet have a credential, so
the command uses the zone key and the `SHARKTRUST-AVAILABLE` proof context.

Request:

```http
POST /sharktrust.lsp HTTP/1.1
Content-Type: application/json
X-SharkTrust-Zone-Key: <zone-key>
X-SharkTrust-Proof: <base64url-hmac-sha-256>
```

```json
{
  "command": "IsAvailable",
  "name": "controller"
}
```

`name` follows the enrollment validation and normalization rules. A successful
response returns the normalized full name and whether it is unused:

```json
{
  "result": {
    "available": true,
    "name": "controller.example.com"
  }
}
```

This check does not reserve the name. `Register` checks the name again while
holding the enrollment lock.

### 6.2 Enrollment

Request:

```http
POST /sharktrust.lsp HTTP/1.1
Content-Type: application/json
X-SharkTrust-Zone-Key: <zone-key>
X-SharkTrust-Proof: <base64url-hmac-sha-256>
```

```json
{
  "command": "Register",
  "name": "controller",
  "namePolicy": "exact",
  "ipAddress": "192.168.1.100",
  "dns": "local",
  "info": "Plant controller"
}
```

| Member | Required | Contract |
| --- | --- | --- |
| `command` | Yes | Must be the case-sensitive value `Register`. |
| `name` | No | DNS label or full name in the selected zone. Defaults to `device`. The label contains 1 to 63 lowercase letters, digits, or hyphens and cannot start or end with a hyphen. |
| `namePolicy` | No | `exact` or `increment`. With an explicit name, the default is `exact`. The field has no effect when `name` is omitted. |
| `ipAddress` | Yes | IPv4 address in dotted-decimal form. |
| `dns` | No | `local`, `wan`, or `both`. Defaults to `local`. |
| `info` | No | Printable UTF-8 device description of at most 256 bytes. |

The `dns` value determines which address the portal publishes:

- `local` publishes the address supplied in `ipAddress`.
- `wan` publishes the public peer address observed by the portal.
- `both` publishes both addresses when they differ.

SharkTrust does not create a NAT rule, port-forwarding rule, or firewall rule.
Use a reverse connection when the device must be reachable through the portal
without an inbound network route.

With `namePolicy` set to `exact`, an occupied name returns HTTP 409
`name_unavailable`. With `namePolicy` set to `increment`, the portal first tries
the requested name and then appends a number until it finds an available label.
For example, it tries `controller1`, `controller2`, and so on when `controller`
is occupied.

When `name` is omitted, the portal starts with `device` and applies the same
numbered search regardless of `namePolicy`. Enrollment is not idempotent.

The portal serializes concurrent enrollment requests within a zone and holds
the zone lock until the database write completes. For `exact`, at most one
concurrent request for the same name succeeds. For `increment`, concurrent
requests receive distinct names. If the lock cannot be acquired or the write
fails, the response is HTTP 503 `database_unavailable`.

The portal returns `201 Created`:

```json
{
  "result": {
    "deviceId": "0123456789abcdef0123",
    "name": "controller.example.com",
    "credential": "<64-lowercase-hexadecimal-characters>"
  }
}
```

`deviceId` is a public diagnostic identifier. Authorization does not trust a
client-supplied device identifier.

## 7. Device commands

### 7.1 Request envelope

```http
POST /sharktrust.lsp HTTP/1.1
Content-Type: application/json
Authorization: Bearer <device-credential>
X-SharkTrust-Proof: <base64url-hmac-sha-256>
```

Every command body contains a required, case-sensitive `command` member.

### 7.2 IsRegistered

Request:

```json
{
  "command": "IsRegistered"
}
```

The portal updates the observed WAN address and last-access time. It returns:

```json
{
  "result": {
    "registered": true,
    "deviceId": "0123456789abcdef0123",
    "name": "controller.example.com"
  }
}
```

### 7.3 SetIpAddress

Request:

```json
{
  "command": "SetIpAddress",
  "ipAddress": "192.168.1.101",
  "dns": "both"
}
```

`ipAddress` is required. `dns` is optional and defaults to `local`. The command
updates the local address, observed WAN address, DNS selection, and last-access
time. The result contains the assigned full device name.

### 7.4 SetAcmeRecord

Request:

```json
{
  "command": "SetAcmeRecord",
  "recordName": "_acme-challenge.controller.example.com",
  "recordData": "base64url-acme-authorization",
  "dnsResolveTimeoutMs": 30000
}
```

| Member | Required | Contract |
| --- | --- | --- |
| `recordName` | Yes | Exact `_acme-challenge.<device>.<zone>` name, with an optional final dot. |
| `recordData` | Yes | Base64url value of 1 to 512 characters. |
| `dnsResolveTimeoutMs` | No | Integer from 1000 through 300000. Defaults to 30000. |

The portal replaces the device's temporary TXT value, rebuilds the zone data,
and schedules automatic removal after the requested DNS wait plus 10 seconds.

### 7.5 RemoveAcmeRecord

Request:

```json
{
  "command": "RemoveAcmeRecord"
}
```

The portal removes all temporary ACME TXT records owned by the authenticated
device and rebuilds the zone data.

### 7.6 GetWan

Request:

```json
{
  "command": "GetWan"
}
```

The result contains the peer IPv4 address observed by the portal:

```json
{
  "result": {
    "ipAddress": "203.0.113.10"
  }
}
```

## 8. Authorization and isolation

- The portal resolves a device credential to one device row and its owning
  zone.
- Every request MUST include a valid proof derived from that zone's secret.
- A device command MUST NOT accept a client-supplied zone key, zone identifier,
  or device identifier as authorization input.
- `SetAcmeRecord` MUST reject a TXT name outside the authenticated device's
  exact challenge name.
- Removing a device invalidates its credential.
- Authentication failures are limited per peer address in process memory. The
  portal limit is 10 failed attempts in 60 seconds.

## 9. Replay and idempotency

The request proof authenticates the exact body bytes and binds them to the zone
key or device credential. It does not provide application-level replay
detection because the message has no counter, timestamp, or server nonce.
Validated TLS protects the credential and request in transit.

`IsAvailable`, `IsRegistered`, `SetIpAddress`, `SetAcmeRecord`,
`RemoveAcmeRecord`, and `GetWan` are idempotent for the same authenticated
identity and request data. Enrollment is not idempotent.

## 10. Reverse connections

An enrolled device opens a reverse connection with:

```http
GET /sharktrust.lsp HTTP/1.1
Authorization: Bearer <device-credential>
X-SharkTrust-Proof: <base64url-hmac-sha-256-over-the-empty-body>
```

The proof uses the `SHARKTRUST-DEVICE` message with an empty request body. After
authentication, the portal returns `202 Accepted` and transfers the connection
to its reverse-connection bridge. The client keeps one such connection open.
After the bridge consumes it for a browser request, the client opens the next
reverse connection.

If browser requests arrive faster than replacement device connections, the
portal holds a bounded first-in, first-out queue of browser sockets for that
device. Each newly authenticated device socket is paired with the oldest
waiting browser socket. A queue entry that cannot be paired within the portal's
timeout receives `503 Service Unavailable`. Clients may retry according to the
`Retry-After` header.

## 11. Conformance requirements

A conforming implementation must be tested for:

- HTTPS and certificate validation;
- method, media-type, and body-size rejection;
- missing and invalid zone keys and device credentials;
- missing, invalid, and body-mismatched request proofs;
- available and occupied explicit-name checks;
- enrollment, invalid name-policy rejection, exact-name conflict rejection,
  incremented-name assignment, and automatic unique-name assignment;
- every command in Section 7;
- rejection of an ACME record outside the authenticated device name;
- malformed JSON, invalid fields, and an unknown command;
- repeated idempotent commands;
- portal restart with the stored device credential; and
- reverse-connection authentication, socket replacement, first-request POST,
  concurrent browser requests, queue timeout, and reconnect recovery.

Public DNS answers, BIND validation, ACME issuance, and end-to-end reverse
connections require a live Linux portal and a delegated test zone.
