# BACME
 Automated Certificate Management and DNS Server


```console
apt-get update
apt-get -y upgrade
apt-get -y install git
cd /tmp
git clone https://github.com/RealTimeLogic/BACME.git
cd BACME
chmod +x INSTALL.sh
./INSTALL.sh
```



```lua
settings={
   ns1="acme1.realtimelogic.com",
   ns2="acme2.realtimelogic.com",
   dn="acme.realtimelogic.com",
   acme={
      production=true,
      rsa=true
   }
}

log={
   logerr = true, -- Send Lua LSP exceptions by email
   signature="-- Sent from Real Time Logic's Let's Encrypt DNS Service",
   smtp={
      See documentation: https://realtimelogic.com/ba/doc/en/Mako.html#oplog
   }
}
```
