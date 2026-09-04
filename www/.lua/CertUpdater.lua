local wait4DNSTime=12000

local fmt=string.format
local Engine=require"acme/engine"
local engine=assert(Engine.create())
local install=require"acme/_server"(ba.tpm)
local hio = ba.openio"home"
if not hio:stat"acmecert" and not hio:mkdir"acmecert" then
   error("Cannot create directory "..hio:realpath"acmecert")
end
local aio=ba.mkio(hio,"acmecert")
local db=require"ZoneDB"
local rw=require"rwfile"
local profile,service,certKey=""

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

local function tpmKey(value,name,curve)
   if type(value) == "string" then
      local old=ba.json.decode(value)
      value={provider="tpm",name=old.keyname,options={curve=old.curve or curve}}
   elseif not value then
      value={provider="tpm",name=name,options={curve=curve}}
   end
   if not ba.tpm.haskey(value.name) then ba.tpm.createkey(value.name,value.options) end
   return value
end

-- Read or write the account table and migrate former field names in memory.
local function account(accountT)
   if accountT then return rw.json(aio,profile.."account",accountT) end
   accountT=rw.json(aio,profile.."account") or {email=admEmail}
   accountT.url=accountT.url or accountT.id
   accountT.id=nil
   accountT.directoryUrl=accountT.directoryUrl or service.directoryUrl
   accountT.key=tpmKey(accountT.key,"$account","SECP256R1")
   return accountT
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


local function challenge(name,setDnsRecCB,remDnsRecCB)
   if not setDnsRecCB then return end
   return {
      type="dns-01",
      present=function(_,context,resumeCB)
         setDnsRecCB(name,context.recordName,context.recordData)
         ba.timer(function() resumeCB(true) end):set(wait4DNSTime,true)
      end,
      cleanup=function(_,context,resumeCB)
         remDnsRecCB(name,context.recordName)
         resumeCB(true)
      end
   }
end


local function updateCert(nameT, name, onDoneCB, setDnsRecCB, remDnsRecCB)
   nameT[name] = ba.datetime"MAX" -- stop trying to update
   local accountT=account()
   local function onCert(result,problem)
      if result then
         clearRetry(certRetryT,name)
         nameT[name] = getCertExpDate(name,result.certificate)
         account(result.account)
         log(false,"%s certificate %s",rCert(name) and "Updating" or "Creating", fmtCert(name))
         wCert(name,result.certificate)
      else
         nameT[name] = ba.datetime"MIN"
         log(true,"Certificate request error '%s': %s",name,
             type(problem)=="table" and (problem.message or problem.code) or tostring(problem))
         scheduleRetry(certRetryT,name,"regular")
      end
      onDoneCB()
   end
   engine:certificate(service,accountT,{domain=name,acceptTerms=true,
      challenge=challenge(name,setDnsRecCB,remDnsRecCB),key={privateKey=certKey}},onCert)
end

-- Create/update the wildcard certificate for name (domain).
local function updateWildcardCert(name, setDnsRecCB, remDnsRecCB, onDoneCB)
   local accountT=account()
   local function onCert(result,problem)
      if result then
         clearRetry(wildcardRetryT,name)
         account(result.account)
         log(false,"%s certificate %s",rCert(name,true) and "Updating" or "Creating", fmtCert(name,true))
         wCert(name,result.certificate,true)
      else
         log(true,"Certificate request error '%s': %s",name,
             type(problem)=="table" and (problem.message or problem.code) or tostring(problem))
         scheduleRetry(wildcardRetryT,name,"wildcard")
      end
      onDoneCB()
   end
   engine:certificate(service,accountT,{domain="*."..name,acceptTerms=true,
      challenge=challenge(name,setDnsRecCB,remDnsRecCB),key={privateKey=certKey}},onCert)
end

local function loadCert(certsL,nameT,wildcard)
   for name in pairs(nameT) do
      local cert = rCert(name,wildcard)
      tracep(9,fmt("%s%s",wildcard and "*." or "", name), cert and "OK" or "failed!")
      if cert then
         table.insert(certsL,{privateKey=certKey,certificate=cert})
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
   profile=op.production == false and "staging." or ""
   admEmail=aEmail
   local production=op.production ~= false
   service={production=production,productionUrl=op.productionUrl,stagingUrl=op.stagingUrl,
      directoryUrl=production and (op.productionUrl or "https://acme-v02.api.letsencrypt.org/directory") or
         (op.stagingUrl or "https://acme-staging-v02.api.letsencrypt.org/directory")}
   for name in pairs(zonesT) do zonesT[name]=getCertExpDate(name) end
   -- The private key used for all certs
   local privkey = rw.file(aio,"privkey.key")
   if not privkey then
      if op.rsa then log(false,"Creating RSA private key") end
      privkey=op.rsa and engine:createKey("SharkTrustX.PrivKey",{type="rsa",bits=op.bits}) or
         tpmKey(nil,"SharkTrustX.PrivKey",op.curve or "SECP384R1")
      if type(privkey) == "string" then rw.file(aio,"privkey.key",privkey) end
   end
   certKey=privkey
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
            local certsL={}
            loadCert(certsL,domainsT,false)
            loadCert(certsL,zonesT,false)
            loadCert(certsL,zonesT,true)
            if #certsL > 0 then
               install(certsL,function(ok,problem)
                  if not ok then log(true,"Creating shark-cert failed: %s",tostring(problem)) end
               end)
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
