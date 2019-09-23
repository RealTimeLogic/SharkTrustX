The Barracuda Automatic Certificate Management Environment Protocol

## 1 Introduction

The BACME protocol together with the ACME protocol enables web servers deployed within private networks to automate the certificate management process. BACME is a simple protocol that facilities setting the required DNS text record needed as proof of domain ownership.

## 2 Acronyms and Definitions:

* **HTTP:** Hypertext Transfer Protocol
* **ACME** : Automatic Certificate Management Environment Protocol (RFC- 8555)
* **BACME** : the protocol specified below

## 3 Message Types

The device to BACME service request is sent as an HTTPS GET. The service responds with a 201 response for successful requests, 204 if the X-Key and/or X-Dev was not found, and 401 if the request was denied. The server may return a 500 response if anything unexpected happens on the server side. HTTP responses do not include a body. All data is exchanged using HTTP headers.

A 204, 401, 500 response includes the following:

| X-Reason | 204: message such as X-Key not found or X-Dev not found401: The reason for the request being denied |

### GetWan

Request online service to send the client's public WAN address.

**HTTP Request Headers:**

| Key | Value |
| --- | --- |
| X-Command | GetWan |

**HTTP Response Headers:**

| Key | Value |
| --- | --- |
| X-IpAddress | The public IP address |

### Register

The Register command is sent by an uninitialized device. The Register command registers the device with the BACME service.

**HTTP Request Headers:**

| Key | Value |
| --- | --- |
| X-Command | Register |
| X-Key | The 40 byte zone key (password) created when signing up for the BACME Service. |
| X-IpAddress | The IP address of the device as registered by the device's Ethernet port either by static configuration or DHCP. The format must be such that it can be used by DNS Bind -- e.g. 192.168.1.100 |
| X-Name | Optional name such as product name. The name, if provided, is used for constructing the final domain name for the device -- e.g. product[n].company.com. If no name is provided, the device is named device[n]. |
| X-Info | Optional information describing the product in more detail. |

**HTTP Response Headers:**

| Key | Value |
| --- | --- |
| X-Dev | The 20 byte Device key. |
| X-Name | The DNS name selected by the server is the same as the X-Name if no other device has this name. |

### SetIpAddress

Send the device IP address to the BACME service and update the DNS. A recommendation is to send this command each time the device starts or reboots.

**HTTP Request Headers:**

| Key | Value |
| --- | --- |
| X-Command | SetIpAddress |
| X-Key | The 40 byte zone key |
| X-Dev | The 20 byte device key |
| X-IpAddress | The IP address of the device as registered by the device's Ethernet port either by static configuration or DHCP. The format must be such that it can be used by DNS Bind -- e.g. 192.168.1.100 |

**HTTP Response Headers:**

| Key | Value |
| --- | --- |
| X-Name | The DNS name selected by the server is the same as the X-Name if no other device has this name. |

### SetAcmeRecord

**HTTP Request Headers:**

| Key | Value |
| --- | --- |
| X-Command | SetAcmeRecord |
| X-Key | The 40 byte zone key |
| X-Dev | The 20 byte device key |
| X-RecordName | The record name requested by the ACME Let's Encrypt Server |
| X-RecordData | The record value computed by the Barracuda Server's ACME plugin |

**HTTP Response Headers**

No response headers are returned for a successful (201) response.

### RemoveAcmeRecord

**HTTP Request Headers:**

| Key | Value |
| --- | --- |
| X-Command | RemoveAcmeRecord |
| X-Key | The 40 byte zone key |
| X-Dev | The 20 byte device key |

**HTTP Response Headers**

No response headers are returned for a successful (201) response.
