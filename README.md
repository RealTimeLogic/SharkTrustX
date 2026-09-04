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
