local fmt=string.format
local acme = require"acme/engine"
local hio = ba.openio"home"
if not hio:stat"acmecert" and not hio:mkdir"acmecert" then
   error("Cannot create directory "..hio:realpath"acmecert")
end
local aio=ba.mkio(hio,"acmecert")
local db=require"ZoneDB"
local rw=require"rwfile"

-- List of "static" domains used by server. Key=domain,val=exptime (DateTime)
local domainsT={}
-- List of all registered zone names. Key=domain,val=exptime (DateTime)
-- We create a wildcard cert and a regular cert for each zone
local zonesT={}
local zonesTMod=false

-- System's registered main contact
local admEmail

-- Options used with acme.cert(...,op)
local acmeOP

-- Read or write account table
local function account(accountT)
   return rw.json(aio,"account",accountT)
end

-- Create and return certificate name
local function fmtCert(name,wildcard)
   return fmt(wildcard and "%s.wildcardcert" or "%s.cert",name)
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



local function updateCert(nameT, name, onDoneCB)
   nameT[name] = ba.datetime"MAX" -- stop trying to update
   local accountT=account() or {email=admEmail}
   local function onCert(key,cert)
      if key then
         assert(key == acmeOP.privkey)
         nameT[name] = getCertExpDate(name,cert)
         account(accountT) -- May have been updated
         log(false,"%s certificate %s",rCert(name) and "Updating" or "Creating", fmtCert(name))
         wCert(name,cert)
      else
         log(true, "Certificate request error '%s': %s",name, cert)
      end
      onDoneCB()
   end
   acme.cert(accountT, name, onCert, acmeOP)
end

-- Create/update both certificate and wildcard cert for name (domain).
-- Executes in the order (1) to (6) where (6) resumes coroutine caller 'onDoneCB'
local function updateWildcardCert(name, onlyWcCert, setDnsRecCB, remDnsRecCB, onDoneCB)
   local function doWildcardCert() -- (2)
      -- Copy table
      local op = {} for k,v in pairs(acmeOP) do op[k]=v end
      op.ch = {
         type ="dns-01",
         set=function(dnsRecord, dnsData, resumeCB) -- (3)
            setDnsRecCB(name, dnsRecord, dnsData)
            ba.timer(function() resumeCB(true) end):set(120000, true)
         end,
         remove=function(resumeCB,na,dnsRecord) -- (4)
            remDnsRecCB(name, dnsRecord)
            resumeCB(true)
         end,
      }
      local accountT=account()
      local function onCert(key,cert) -- (5)
         if cert and key == acmeOP.privkey then
            account(accountT) -- May have been updated
            log(false,"%s certificate %s",rCert(name,true) and "Updating" or "Creating", fmtCert(name,true))
            wCert(name,cert,true)
         else
            log(true, "Certificate request error '%s': %s : %s",name, key, cert)
         end
         onDoneCB() -- (6)
      end
      acme.cert(accountT, "*."..name, onCert, op)
   end
   if onlyWcCert then
      doWildcardCert()
   else
      updateCert(zonesT, name, doWildcardCert) -- (1)
   end
end

local function loadCert(certsL,nameT,wildcard)
   for name in pairs(nameT) do
      local cert = rCert(name,wildcard)
      tracep(9,wildcard and "*." or "", name, cert and "OK" or "failed!")
      if cert then
         table.insert(certsL, cert)
      else
         log(false, "Cert %s not found",fmtCert(name,wildcard))
      end
   end
end

local function start(domainsL, setDnsRecCB, remDnsRecCB, aEmail, op)
   -- The private key used for all certs
   local privkey = rw.file(aio,"privkey.key")
   if not privkey then
      local kop = op.rsa == true and {key="rsa",bits=op.bits} or {curve=op.curve or "SECP384R1"}
      log(false, "Creating private key")
      privkey=ba.create.key(kop)
      rw.file(aio,"privkey.key",privkey)
   end
   for _,domain in ipairs(domainsL) do
      domainsT[domain] = getCertExpDate(domain)
   end
   acmeOP=op
   acmeOP.privkey=privkey
   admEmail=aEmail

   -- Auto certificate update
   local busy=false
   local certUpdaterCo
   certUpdaterCo = coroutine.wrap(function()
      local updated=true -- Load certs @ startup
      while true do
         local minDate = ba.datetime("NOW", {days=20}) -- Now + 20 days
         for name,expDate in pairs(domainsT) do
            if expDate < minDate then
               busy=true
               updateCert(domainsT, name, certUpdaterCo)
               coroutine.yield()
               busy=false
               updated=true
            end
         end
         for name,expDate in pairs(zonesT) do
            if expDate <= minDate or not aio:stat(fmtCert(name,true)) then
               busy=true
               updateWildcardCert(name, expDate > minDate, setDnsRecCB, remDnsRecCB, certUpdaterCo)
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
                  local scert,err = ba.create.sharkcert(cert, acmeOP.privkey)
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
   zonesT[zone]=getCertExpDate(zone)
   zonesTMod=true
end

local function removeZone(zone)
   zonesT[zone]=nil
   zonesTMod=true
   aio:remove(fmtCert(zone))
   aio:remove(fmtCert(zone,true))
end

return {
   start=start,
   addZone=addZone,
   removeZone=removeZone
}
