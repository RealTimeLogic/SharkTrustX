# BACME
Automated Certificate Management and DNS Server

This repository contains the source code for [Real Time Logic's Let's encrypt DNS Service](https://acme.realtimelogic.com/) and a ready to use installation script, making it easy for anyone to set up their own online service replica. The service is designed to run on one online VPS and uses [bind](https://en.wikipedia.org/wiki/BIND) for the DNS management. The bind service is controlled by a Lua powered application running on a Mako Server instance.

**NOTE:** The following domain names are used in the instructions below and these names must be replaced by your own names such as xx.company.com.

* **Name server 1:** acme1.realtimelogic.com
* **Name server 2:** acme2.realtimelogic.com
* **Service's domain name:** acme.realtimelogic.com

The software requires two name servers listed in the configuration file, however, the software is currently limited to running on one VPS and the DNS A record for the three fields above must all point to the same VPS.

## Installation Instructions

**1:** Sign up for a VPS provider and install a Debian distribution, preferably Debian minimal. See the tutorial [Setting up a Low Cost SMQ IoT Broker](https://makoserver.net/articles/Setting-up-a-Low-Cost-SMQ-IoT-Broker) if you are new to VPS or if you want to know more about how the Mako Server is installed on the online VPS by the installation script.

**2:** After signing up for a VPS Service, take note of the online server's IP address, navigate to your company's DNS settings page, and add A text records for xx1.company.com, xx2.company.com, and xx.company.com, where xx is a sub domain such as 'acme' and company.com is your company name or any other domain name you own. All A records must point to the VPS IP address.

**3:** Wait 24 hours for the DNS settings to take effect.

**4:** Login to the online VPS using SSH, and run the following set of commands in the SSH shell:

### Update Linux
```console
apt-get update
apt-get -y upgrade
```

### Install GIT
```console
apt-get -y install git
```

### Clone GIT repo in /tmp and run the installation script
```console
cd /tmp
git clone https://github.com/RealTimeLogic/BACME.git
cd BACME
chmod +x INSTALL.sh
./INSTALL.sh
```

Carefully follow the instructions provided by the installation script. The script is as a sub component using the installation script provided in the Setting up a Low Cost SMQ IoT Broker tutorial.

When the installation is complete, the installation script opens /home/mako/mako.conf in the nano editor. Do not modify any of the entries in the configuration file. Add the following to the end of mako.conf. **Note:** as explained above, the following must be edited and completed.


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
Save the changes and start the mako server as follows in /home/mako as user 'root'

```console
mako
```
You should see the following being printed in the console two minutes after starting the Mako Server.

```console
ACME: acme.realtimelogic.com renewed
```
The printout should be for your own service's domain name. The above printout signals that the service is operational. You may now terminate the Mako Server process by using CTRL-C and then start the service as a background processes:

```console
/etc/init.d/mako.sh start
```

You may now use a browser and navigate to xx.company.com (e.g. acme.realtimelogic.com)
