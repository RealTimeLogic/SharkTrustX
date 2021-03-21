# SharkTrustX

SharkTrust eXtended (SharkTrustX) is an extended version of [SharkTrust](https://github.com/RealTimeLogic/SharkTrust) that provides additional features such as remote access of private servers. Unlike SharkTrust, which works with any web server, SharkTrustX is designed exclusively for [Barracuda App Server](https://realtimelogic.com/products/barracuda-application-server/) powered products such as the [Mako Server](https://makoserver.net/).

SharkTrustX is a free product released under the MIT License. See the [SharkTrustX product page](https://realtimelogic.com/products/SharkTrustX/) for additional information.

**NOTE:** The following domain names are used in the instructions below. Replace these names with your own such as xx.company.com.

* **Name server 1:** acme1.realtimelogic.com
* **Name server 2:** acme2.realtimelogic.com
* **Service's domain name:** acme.realtimelogic.com

The software requires two name servers listed in the configuration file. However, the software is currently limited to running on one VPS and the DNS A record for the three fields above must all point to the same VPS.

## Customizing SharkTrustX

1. Fork or clone this repository.
2. Customize the template with your own logos and color options. The [template page](www/.lua/www/template.lsp) is based on the  AdminLTE Bootstrap template. See the Mako Server tutorial [How to Build an Interactive Dashboard App](https://makoserver.net/articles/How-to-Build-an-Interactive-Dashboard-App) for details.


## Installation Instructions

**1:** Sign up for a VPS provider and install a Debian (derivative) distribution.

**2:** After signing up for a VPS Service, take note of the online server's IP address, navigate to your company's DNS settings page, and add A text records for xx1.company.com, xx2.company.com, and xx.company.com, where xx is a sub domain such as 'acme' and company.com is your company name or any other domain name you own. All A records must point to the VPS IP address.

**3:** Wait 24 hours for the DNS settings to take effect.

**4:** Login to the online VPS using SSH, and run the following set of commands in the SSH shell:

### Update Linux
```console
apt-get update
apt-get -y upgrade
```

### Install Required Applications
```console
apt-get -y install git bind9 whois lsof git nano
```

### Clone GIT repo in a suitable directory
```console
git clone https://github.com/RealTimeLogic/SharkTrustX.git
```

### Configure the Mako Server

Create a mako.conf script and add instructions for loading SharkTrustX

```lua
apps = {
   { name='', path='SharkTrustEx/www'},
}
```

Add the following to mako.conf:


```lua
-- The following settings are used by the Lua code in /home/mako/www
settings={
   ns1="acme1.realtimelogic.com",
   ns2="acme2.realtimelogic.com",
   dn="acme.realtimelogic.com",
   acme={
      production=true,
      rsa=true
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
Save the changes and start the Mako Server as as user 'root'

```console
mako
```
You should see the following being printed in the console two minutes after starting the Mako Server.

```console
ACME: acme.realtimelogic.com renewed
```
The printout should be for your own service's domain name. The above printout signals that the service is operational. You may now terminate the Mako Server process by using CTRL-C and then [install the Mako Server as a service](https://makoserver.net/articles/Installing-Mako-Server-as-a-Service-on-Linux).

You may now use a browser and navigate to xx.company.com (e.g. acme.realtimelogic.com)
