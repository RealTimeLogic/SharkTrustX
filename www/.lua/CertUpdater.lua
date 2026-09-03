local wait4DNSTime=12000

local fmt=string.format
local acme = require"acme/engine"
local hio = ba.openio"home"
if not hio:stat"acmecert" and not hio:mkdir"acmecert" then
   error("Cannot create directory "..hio:realpath"acmecert")
end
local aio=ba.mkio(hio,"acmecert")
local db=require"ZoneDB"
local rw=require"rwfile"
local profile=""

-- List of "static" domains used by server. Key=domain,val=exptime (DateTime)
local domainsT={}
-- List of all registered zone names. Key=domain,val=exptime (DateTime)
-- We create a wildcard cert and a regular cert for each zone
local zonesT={}
local zonesTMod=false

-- Retry failed ACME requests with bounded backoff. Certificate expiration and
-- retry scheduling are separate states: using an expiration sentinel for both
-- can suppress a failed request until the process restarts.
local retryDelays={60,300,900,3600,21600}
local certRetryT={}
local wildcardRetryT={}

local function retryReady(retryT,name)
   local retry=retryT[name]
   return not retry or retry.at <= ba.datetime"NOW"
end

local function clearRetry(retryT,name)
   retryT[name]=nil
end

local function scheduleRetry(retryT,name,certType)
   local retry=retryT[name] or {attempt=0}
   retry.attempt=math.min(retry.attempt+1,#retryDelays)
   local delay=retryDelays[retry.attempt]
   retry.at=ba.datetime("NOW",{secs=delay})
   retryT[name]=retry
   log(false,"Retrying %s certificate '%s' in %d seconds",certType,name,delay)
end

-- System's registered main contact
local admEmail

-- Options used with acme.cert(...,op)
local acmeOP

-- Read or write account table
local function account(accountT)
   return rw.json(aio,profile.."account",accountT)
end

-- Create and return certificate name
local function fmtCert(name,wildcard,prefix)
   return (prefix or profile)..fmt(wildcard and "%s.wildcardcert" or "%s.cert",name)
end
-- Returns key,cert
local function rCert(name,wildcard)
   return rw.file(aio,fmtCert(name,wildcard))
end
local function wCert(name,cert,wildcard)
   return rw.file(aio,fmtCert(name,wildcard),cert)
end


-- Extracts ASN.1 UTC time and returns a DateTime object
-- https://www.obj-sys.com/asn1tutorial/node15.html
-- This function stops working the year 2100
local function getCertExpDate(domainname, cert)
   local tzto
   cert = cert or rCert(domainname)
   pcall(function()
            tzto=ba.parsecert(ba.b64decode(
               cert:match".-BEGIN.-\n%s*(.-)\n%s*%-%-")).tzto
         end)
   if not tzto then
      if cert then -- if created. Not yet created OK
         log(true, "UTCTime parse error for:\n%s",cert)
      end
      return ba.datetime"MIN"
   end
   local exptime = ba.parsecerttime(tzto)
   if exptime ~= 0 then return ba.datetime(exptime) end
   log(true, "UTCTime parse error for: %s\n%s",tzto,cert)
   return ba.datetime"MIN"
end


local function getAcmeOP(name,setDnsRecCB,remDnsRecCB)
   local op = {} for k,v in pairs(acmeOP) do op[k]=v end
   if setDnsRecCB then
      op.ch = {
         type ="dns-01",
         set=function(dnsRecord, dnsData, resumeCB) -- (3)
            setDnsRecCB(name, dnsRecord, dnsData)
            ba.timer(function() resumeCB(true) end):set(wait4DNSTime, true)
         end,
         remove=function(resumeCB,dnsRecord) -- (4)
            remDnsRecCB(name, dnsRecord)
            resumeCB(true)
         end,
      }
   end
   return op
end


local function updateCert(nameT, name, onDoneCB, setDnsRecCB, remDnsRecCB)
   nameT[name] = ba.datetime"MAX" -- stop trying to update
   local op = getAcmeOP(name,setDnsRecCB, remDnsRecCB)
   local accountT=account() or {email=admEmail}
   local function onCert(key,cert)
      if key then
         assert(key == acmeOP.privkey)
         clearRetry(certRetryT,name)
         nameT[name] = getCertExpDate(name,cert)
         account(accountT) -- May have been updated
         log(false,"%s certificate %s",rCert(name) and "Updating" or "Creating", fmtCert(name))
         wCert(name,cert)
      else
         nameT[name] = ba.datetime"MIN"
         log(true, "Certificate request error '%s': %s",name, cert)
         scheduleRetry(certRetryT,name,"regular")
      end
      onDoneCB()
   end
   acme.cert(accountT, name, onCert, op)
end

-- Create/update the wildcard certificate for name (domain).
local function updateWildcardCert(name, setDnsRecCB, remDnsRecCB, onDoneCB)
   local op = getAcmeOP(name,setDnsRecCB, remDnsRecCB)
   local accountT=account() or {email=admEmail}
   local function onCert(key,cert)
      if cert and key == acmeOP.privkey then
         clearRetry(wildcardRetryT,name)
         account(accountT) -- May have been updated
         log(false,"%s certificate %s",rCert(name,true) and "Updating" or "Creating", fmtCert(name,true))
         wCert(name,cert,true)
      else
         -- The callback's key value may contain private-key material.
         log(true, "Certificate request error '%s': %s",name, cert)
         scheduleRetry(wildcardRetryT,name,"wildcard")
      end
      onDoneCB()
   end
   acme.cert(accountT, "*."..name, onCert, op)
end

local function loadCert(certsL,nameT,wildcard)
   for name in pairs(nameT) do
      local cert = rCert(name,wildcard)
      tracep(9,fmt("%s%s",wildcard and "*." or "", name), cert and "OK" or "failed!")
      if cert then
         table.insert(certsL, cert)
      else
         log(false, "Cert %s not found",fmtCert(name,wildcard))
      end
   end
end

local function checkIfWildCertExp(name, minDate)
   local c=rCert(name,true)
   if not c then return true end
   local expDate=getCertExpDate(nil, c)
   return expDate < minDate
end


local function start(domainsL, setDnsRecCB, remDnsRecCB, aEmail, op)
   acmeOP=op
   profile=op.production == false and "staging." or ""
   admEmail=aEmail
   for name in pairs(zonesT) do zonesT[name]=getCertExpDate(name) end
   -- The private key used for all certs
   local privkey = rw.file(aio,"privkey.key")
   if privkey then
      if true == op.rsa then op.privkey=privkey end
   else
      if true == op.rsa then
         log(false, "Creating RSA private key")
         privkey=ba.create.key({key="rsa",bits=op.bits})
         rw.file(aio,"privkey.key",privkey)
         op.privkey=privkey
      else
         op.privkey=acme.createkey("SharkTrustX.PrivKey",{curve=op.curve or "SECP384R1"})
      end
   end
   for _,domain in ipairs(domainsL) do
      domainsT[domain] = getCertExpDate(domain)
   end

   -- Auto certificate update
   local busy=false
   local certUpdaterCo
   certUpdaterCo = coroutine.wrap(function()
      local updated=true -- Load certs @ startup
      while true do
         local minDate = ba.datetime("NOW", {days=20}) -- Now + 20 days
         for name,expDate in pairs(domainsT) do
            if expDate < minDate and retryReady(certRetryT,name) then
               busy=true
               -- Using http-01, not dns-01; (two last args not provided)
               updateCert(domainsT,name,certUpdaterCo)
               coroutine.yield()
               busy=false
               updated=true
            end
         end
         for name,expDate in pairs(zonesT) do
            if expDate <= minDate and retryReady(certRetryT,name) then
               busy=true
               updateCert(zonesT,name,certUpdaterCo,setDnsRecCB,remDnsRecCB)
               coroutine.yield()
               busy=false
               updated=true
            end
            if zonesTMod then break end -- restart if table modified
            if checkIfWildCertExp(name, minDate) and retryReady(wildcardRetryT,name) then
               busy=true
               updateWildcardCert(name,setDnsRecCB,remDnsRecCB,certUpdaterCo)
               coroutine.yield()
               busy=false
               updated=true
            end
            if zonesTMod then break end -- restart if table modified
         end
         if updated then
            local certsL={},{}
            loadCert(certsL,domainsT,false)
            loadCert(certsL,zonesT,false)
            loadCert(certsL,zonesT,true)
            if #certsL > 0 then
               local shark=ba.create.sharkssl(nil,{server=true})
               for _,cert in ipairs(certsL) do
                  local kn=acme.useTPM(acmeOP.privkey)
                  local scert,err
                  if kn then
                     scert,err = ba.tpm.sharkcert(kn, cert)
                  else
                     scert,err = ba.create.sharkcert(cert, acmeOP.privkey)
                  end
                  if scert then
                     shark:addcert(scert)
                  else
                     log(true, "Creating shark-cert failed: %s\n%s", err or "unknown err", cert)
                  end
               end
               local cfg = {shark=shark}
               if ba.slcon then ba.slcon = ba.create.servcon(ba.slcon,cfg) end
               if ba.slcon6 then ba.slcon6 = ba.create.servcon(ba.slcon6,cfg) end
            else
               log(false,"Warn: no certificates to load!")
            end
            updated=false
         end
         if zonesTMod then
            zonesTMod=false
         else
            -- 30 seconds sleep:
            coroutine.yield()
            coroutine.yield()
            coroutine.yield()
         end
      end
   end)
   ba.timer(function() if not busy then certUpdaterCo() end return true end):set(10000,true,true)
end


local function addZone(zone)
   clearRetry(certRetryT,zone)
   clearRetry(wildcardRetryT,zone)
   zonesT[zone]=getCertExpDate(zone)
   zonesTMod=true
end

local function removeZone(zone)
   zonesT[zone]=nil
   clearRetry(certRetryT,zone)
   clearRetry(wildcardRetryT,zone)
   zonesTMod=true
   aio:remove(fmtCert(zone,nil,""))
   aio:remove(fmtCert(zone,true,""))
   aio:remove(fmtCert(zone,nil,"staging."))
   aio:remove(fmtCert(zone,true,"staging."))
end

return {
   start=start,
   addZone=addZone,
   removeZone=removeZone
}
