local fmt = string.format
local lower = string.lower

local MAX_BODY = 4096
local AUTH_WINDOW = 60
local AUTH_LIMIT = 10
local LOCK_TIMEOUT_MS = 5000

local db
local bindUpdateZone
local getRecsTfromZoneT
local peername
local log
local getProofKey
local reverseConnection

local authFailures = {}
local enrollmentLocks = {}

local function hex(bytes)
   return ba.rndbs(bytes):gsub(".", function(c)
      return fmt("%02x", string.byte(c))
   end)
end

local function credentialHash(credential)
   return ba.crypto.hash"sha256"(credential)(true, "hex")
end

local function sendJson(cmd, status, body)
   cmd:setstatus(status)
   cmd:setheader("Cache-Control", "no-store")
   return cmd:json(body, true, true)
end

local function success(cmd, status, result)
   return sendJson(cmd, status, {result=result})
end

local function failure(cmd, status, code, message)
   return sendJson(cmd, status, {
      error={code=code, message=message}
   })
end

local function sendDeferredJson(defresp, status, body)
   local data = ba.json.encode(body)
   defresp:setstatus(status)
   defresp:setheader("Cache-Control", "no-store")
   defresp:setheader("Content-Type", "application/json; charset=utf-8")
   defresp:setcontentlength(#data)
   defresp:send(data)
   defresp:close()
end

local function deferredSuccess(defresp, status, result)
   return sendDeferredJson(defresp, status, {result=result})
end

local function deferredFailure(defresp, status, code, message)
   return sendDeferredJson(defresp, status, {
      error={code=code, message=message}
   })
end

local function deferResponse(response, state)
   local defresp = response:deferred()
   state.defresp = defresp
   return defresp
end

local function methodAndTransport(cmd)
   if not cmd:issecure() then
      failure(cmd, 400, "tls_required", "Validated HTTPS is required.")
      return false
   end
   local method=cmd:method()
   if method == "GET" then return true,true end
   if method ~= "POST" then
      cmd:setheader("Allow", "GET, POST")
      failure(cmd, 405, "method_not_allowed", "Use GET or POST for this endpoint.")
      return false
   end
   local contentType = cmd:header"Content-Type"
   local mediaType = contentType and lower(contentType):match("^%s*([^;%s]+)")
   if mediaType ~= "application/json" then
      failure(cmd, 415, "unsupported_media_type", "Content-Type must be application/json.")
      return false
   end
   return true,false
end

local function readJson(cmd)
   local contentLength = tonumber(cmd:header"Content-Length")
   if contentLength and contentLength > MAX_BODY then
      failure(cmd, 413, "body_too_large", "The JSON body exceeds 4096 bytes.")
      return nil
   end

   local chunks = {}
   local length = 0
   local ok = pcall(function()
      for chunk in cmd:rawrdr(512) do
         length = length + #chunk
         if length > MAX_BODY then return end
         chunks[#chunks + 1] = chunk
      end
   end)
   if not ok then
      failure(cmd, 400, "invalid_json", "The request body is not valid JSON.")
      return nil
   end
   if length > MAX_BODY then
      failure(cmd, 413, "body_too_large", "The JSON body exceeds 4096 bytes.")
      return nil
   end

   local rawBody = table.concat(chunks)
   local decodeOk, data = pcall(ba.json.decode, rawBody)
   if not decodeOk or type(data) ~= "table" then
      failure(cmd, 400, "invalid_json", "The request body is not a JSON object.")
      return nil
   end
   return data, rawBody
end

local function rateState(cmd)
   local address = peername(cmd)
   local now = os.time()
   local state = authFailures[address]
   if state and state.blockedUntil and state.blockedUntil > now then
      return address, state, state.blockedUntil - now
   end
   if not state or now - state.started >= AUTH_WINDOW then
      state = {started=now, count=0}
      authFailures[address] = state
   end
   return address, state
end

local function checkRate(cmd)
   local _, _, retryAfter = rateState(cmd)
   if retryAfter then
      cmd:setheader("Retry-After", tostring(retryAfter))
      failure(cmd, 403, "rate_limited", "Too many authentication failures.")
      return false
   end
   return true
end

local function authFailed(cmd)
   local _, state = rateState(cmd)
   state.count = state.count + 1
   if state.count >= AUTH_LIMIT then
      state.blockedUntil = os.time() + AUTH_WINDOW
   end
   failure(cmd, 401, "invalid_credentials", "The supplied credentials are not valid.")
end

local function authSucceeded(cmd)
   authFailures[peername(cmd)] = nil
end

local function isHex(value, length)
   return type(value) == "string" and #value == length and
      not value:find("[^0-9a-fA-F]")
end

local function constantTimeEquals(left, right)
   if type(left) ~= "string" or type(right) ~= "string" or #left ~= #right then
      return false
   end
   local difference = 0
   for index = 1, #left do
      difference = difference | (left:byte(index) ~ right:byte(index))
   end
   return difference == 0
end

local function verifyProof(cmd, zoneT, context, rawBody)
   local encoded = cmd:header"X-SharkTrust-Proof"
   if type(encoded) ~= "string" or #encoded ~= 43 then return false end
   local decodeOk, supplied = pcall(ba.b64decode, encoded)
   if not decodeOk or type(supplied) ~= "string" or #supplied ~= 32 then
      return false
   end
   local expected = ba.crypto.hash("hmac", "sha256", getProofKey(zoneT))
      (context)(rawBody)(true, "binary")
   return constantTimeEquals(supplied, expected)
end

local function validIPv4(ip)
   if type(ip) ~= "string" then return false end
   local octets = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
   if #octets ~= 4 then return false end
   for _, value in ipairs(octets) do
      local number = tonumber(value)
      if not number or number < 0 or number > 255 or tostring(number) ~= value then
         return false
      end
   end
   return true
end

local function validDnsType(value)
   return value == "local" or value == "wan" or value == "both"
end

local function validNamePolicy(value)
   return value == "exact" or value == "increment"
end

local function deviceLabel(cmd, value, zoneT)
   local name = value or "device"
   if type(name) ~= "string" then
      failure(cmd, 400, "invalid_name", "The device name is not valid.")
      return nil
   end
   name = lower(name)
   local dot = name:find(".", 1, true)
   if dot then
      if name:sub(dot + 1) ~= lower(zoneT.zname) then
         failure(cmd, 400, "invalid_name", "The device name is outside the selected zone.")
         return nil
      end
      name = name:sub(1, dot - 1)
   end
   if #name < 1 or #name > 63 or name:find("[^a-z0-9-]") or
      name:find("^-") or name:find("-$") then
      failure(cmd, 400, "invalid_name", "The device name is not a valid DNS label.")
      return nil
   end
   if #(name .. "." .. zoneT.zname) > 253 then
      failure(cmd, 400, "invalid_name", "The full device name is too long.")
      return nil
   end
   return name
end

local function writeCallback(defresp, status, result, afterCommit, onComplete)
   return function(ok, err, ...)
      if ok and afterCommit then
         local callbackOk, callbackErr = pcall(afterCommit)
         if not callbackOk then
            log(true, "SharkTrust post-commit action failed: %s", callbackErr)
         end
      end
      if onComplete then
         local completeOk, completeErr = pcall(onComplete)
         if not completeOk then
            log(true, "SharkTrust completion action failed: %s", completeErr)
         end
      end
      if not ok then
         return deferredFailure(defresp, 503, "database_unavailable",
            "The database write did not complete.")
      end
      if type(result) == "function" then
         local resultOk, value = pcall(result, ...)
         if not resultOk then
            log(true, "SharkTrust response creation failed")
            return deferredFailure(defresp, 500, "internal_error",
               "The portal could not complete the request.")
         end
         result = value
      end
      return deferredSuccess(defresp, status, result)
   end
end

local function zoneAuthentication(cmd, rawBody, purpose)
   if not checkRate(cmd) then return nil end
   local key = cmd:header"X-SharkTrust-Zone-Key"
   if not isHex(key, 64) then
      authFailed(cmd)
      return nil
   end
   key = lower(key)
   local zoneT = db.zkeyGetZoneT(key)
   if not zoneT or not verifyProof(cmd, zoneT,
      purpose .. key .. "\0", rawBody) then
      authFailed(cmd)
      return nil
   end
   authSucceeded(cmd)
   return zoneT
end

local function deviceAuthentication(cmd, rawBody)
   if not checkRate(cmd) then return nil end
   local header = cmd:header"Authorization"
   local scheme, credential
   if header then scheme, credential = header:match("^(%S+)%s+(%S+)$") end
   if not scheme or lower(scheme) ~= "bearer" or not isHex(credential, 64) or
      credential:find("[A-F]") then
      authFailed(cmd)
      return nil
   end
   local devT = db.credentialHashGetDeviceT(credentialHash(credential))
   if not devT then
      authFailed(cmd)
      return nil
   end
   local zoneT = db.zidGetZoneT(devT.zid)
   if not zoneT or not verifyProof(cmd, zoneT,
      "SHARKTRUST-DEVICE\0" .. credential .. "\0", rawBody) then
      authFailed(cmd)
      return nil
   end
   authSucceeded(cmd)
   return credential, devT, zoneT
end

local function commandRegister(cmd, response, data, rawBody, deferredState)
   local zoneT = zoneAuthentication(cmd, rawBody, "SHARKTRUST-REGISTER\0")
   if not zoneT then return end

   if not validIPv4(data.ipAddress) then
      return failure(cmd, 400, "invalid_ip_address", "ipAddress must be an IPv4 address.")
   end
   local dns = data.dns or "local"
   if not validDnsType(dns) then
      return failure(cmd, 400, "invalid_dns_mode", "dns must be local, wan, or both.")
   end
   local info = data.info or ""
   if type(info) ~= "string" or #info > 256 or info:find("%c") then
      return failure(cmd, 400, "invalid_info", "info must be printable and at most 256 bytes.")
   end
   local explicitName=data.name ~= nil
   local namePolicy=data.namePolicy or (explicitName and "exact" or "increment")
   if not validNamePolicy(namePolicy) then
      return failure(cmd,400,"invalid_name_policy","namePolicy must be exact or increment.")
   end
   local name = deviceLabel(cmd, data.name, zoneT)
   if not name then return end

   local original = name
   local lockKey=zoneT.zid
   local locked=false
   for _ = 1, LOCK_TIMEOUT_MS // 10 do
      if not enrollmentLocks[lockKey] then
         enrollmentLocks[lockKey]=true
         locked=true
         break
      end
      ba.sleep(10)
   end
   if not locked then
      return failure(cmd, 503, "database_unavailable", "Device enrollment is busy.")
   end

   local queued=false
   local ok,resultOrError=xpcall(function()
      if explicitName and namePolicy == "exact" and db.nameGetDeviceT(zoneT.zid,name) then
         return failure(cmd,409,"name_unavailable","The requested device name is already in use.")
      end
      if not explicitName or namePolicy == "increment" then
         local suffix = 0
         while db.nameGetDeviceT(zoneT.zid, name) do
            suffix = suffix + 1
            local digits = tostring(suffix)
            name = original:sub(1, 63 - #digits) .. digits
         end
      end

      local rname = db.zoneRname(zoneT.zid)
      if #rname > 0 then rname = rname .. name end
      local credential,peer = hex(32),peername(cmd)
      local defresp = deferResponse(response, deferredState)
      local dkey = db.addDeviceV2(
         zoneT.zkey, name, rname, data.ipAddress, peer, dns, info,
         credentialHash(credential),
         writeCallback(
            defresp,
            201,
            function(committedDkey)
               return {
                  deviceId=committedDkey,
                  name=fmt("%s.%s", name, zoneT.zname),
                  credential=credential
               }
            end,
            function() bindUpdateZone(zoneT) end,
            function() enrollmentLocks[lockKey]=nil end
         )
      )
      if not dkey then
         enrollmentLocks[lockKey]=nil
         return deferredFailure(defresp, 500, "enrollment_failed",
            "The device could not be enrolled.")
      end
      queued=true
   end,debug.traceback)
   if not queued then enrollmentLocks[lockKey]=nil end
   if not ok then
      error(resultOrError)
   end
   return resultOrError
end

local function commandIsAvailable(cmd, _, data, rawBody)
   local zoneT=zoneAuthentication(cmd,rawBody,"SHARKTRUST-AVAILABLE\0")
   if not zoneT then return end
   local name=deviceLabel(cmd,data.name,zoneT)
   if not name then return end
   return success(cmd,200,{available=not db.nameGetDeviceT(zoneT.zid,name),
      name=fmt("%s.%s",name,zoneT.zname)})
end

local function commandIsRegistered(cmd, _, devT, zoneT, response, deferredState)
   local peer = peername(cmd)
   local defresp = deferResponse(response, deferredState)
   local callback = writeCallback(defresp, 200, {
      registered=true,
      deviceId=devT.dkey,
      name=fmt("%s.%s", devT.name, zoneT.zname)
   })
   if devT.wanAddr ~= peer then
      db.updateAddress4Device(devT.dkey, devT.localAddr, peer, devT.dns,
         callback)
   else
      db.updateTime4Device(devT.dkey, callback)
   end
end

local function commandSetIpAddress(cmd, data, devT, zoneT, response, deferredState)
   if not validIPv4(data.ipAddress) then
      return failure(cmd, 400, "invalid_ip_address", "ipAddress must be an IPv4 address.")
   end
   local dns = data.dns or "local"
   if not validDnsType(dns) then
      return failure(cmd, 400, "invalid_dns_mode", "dns must be local, wan, or both.")
   end
   local peer=peername(cmd)
   local defresp = deferResponse(response, deferredState)
   db.updateAddress4Device(devT.dkey, data.ipAddress, peer, dns,
      writeCallback(
         defresp,
         200,
         {name=fmt("%s.%s", devT.name, zoneT.zname)},
         function() bindUpdateZone(zoneT) end
      ))
end

local function commandSetAcmeRecord(cmd, data, devT, zoneT)
   local recordName = data.recordName
   local recordData = data.recordData
   if type(recordName) ~= "string" or #recordName > 253 then
      return failure(cmd, 400, "invalid_record_name", "recordName is not valid.")
   end
   recordName = lower(recordName):gsub("%.$", "")
   local expected = fmt("_acme-challenge.%s.%s", lower(devT.name), lower(zoneT.zname))
   if recordName ~= expected then
      return failure(cmd, 400, "record_not_authorized", "The ACME record is outside this device name.")
   end
   if type(recordData) ~= "string" or #recordData < 1 or #recordData > 512 or
      recordData:find("[^A-Za-z0-9_-]") then
      return failure(cmd, 400, "invalid_record_data", "recordData must be a base64url value.")
   end
   local timeout = data.dnsResolveTimeoutMs or 30000
   if type(timeout) ~= "number" or timeout ~= math.floor(timeout) or
      timeout < 1000 or timeout > 300000 then
      return failure(cmd, 400, "invalid_timeout", "dnsResolveTimeoutMs is outside the allowed range.")
   end

   local recsT = getRecsTfromZoneT(zoneT)
   local recT = {}
   recsT[devT.dkey] = recT
   recT[recordName] = '"' .. recordData .. '"'
   ba.timer(function()
      if recsT[devT.dkey] == recT then
         recsT[devT.dkey] = nil
         bindUpdateZone(zoneT)
      end
   end):set(timeout + 10000, true)
   bindUpdateZone(zoneT)
   db.updateTime4Device(devT.dkey)
   return success(cmd, 200, {set=true})
end

local function commandRemoveAcmeRecord(cmd, _, devT, zoneT)
   local recsT = getRecsTfromZoneT(zoneT)
   recsT[devT.dkey] = nil
   bindUpdateZone(zoneT)
   return success(cmd, 200, {removed=true})
end

local function commandGetWan(cmd)
   return success(cmd, 200, {ipAddress=peername(cmd)})
end

local commandHandlers = {
   IsRegistered=commandIsRegistered,
   SetIpAddress=commandSetIpAddress,
   SetAcmeRecord=commandSetAcmeRecord,
   RemoveAcmeRecord=commandRemoveAcmeRecord,
   GetWan=commandGetWan
}

local zoneCommandHandlers={Register=commandRegister,IsAvailable=commandIsAvailable}

local function command(cmd, response, deferredState)
   local valid,isReverse=methodAndTransport(cmd)
   if not valid then return end
   if isReverse then
      local _,devT,zoneT=deviceAuthentication(cmd,"")
      if not devT then return end
      cmd:setstatus(202)
      cmd:flush()
      return reverseConnection(zoneT,devT,ba.socket.req2sock(cmd))
   end
   local data, rawBody = readJson(cmd)
   if not data then return end
   local handler=zoneCommandHandlers[data.command]
   if handler then return handler(cmd,response,data,rawBody,deferredState) end
   local _, devT, zoneT = deviceAuthentication(cmd, rawBody)
   if not devT or not zoneT then return end
   handler = commandHandlers[data.command]
   if not handler then
      return failure(cmd, 400, "unknown_command", "The command is not supported.")
   end
   return handler(cmd, data, devT, zoneT, response, deferredState)
end

local function safe(handler, cmd, response)
   local deferredState = {}
   local function onError(err)
      -- The error may include attacker-controlled request data. Keep the stack
      -- for diagnosis without copying the error value into operational logs.
      log(true, "%s", debug.traceback("SharkTrust internal request failure",2))
      return err
   end
   local ok = xpcall(handler, onError, cmd, response, deferredState)
   if not ok then
      if deferredState.defresp then
         pcall(deferredFailure, deferredState.defresp, 500, "internal_error",
            "The portal could not complete the request.")
      else
         failure(cmd, 500, "internal_error", "The portal could not complete the request.")
      end
   end
end

local function init(options)
   db = assert(options.db)
   bindUpdateZone = assert(options.bindUpdateZone)
   getRecsTfromZoneT = assert(options.getRecsTfromZoneT)
   peername = assert(options.peername)
   log = assert(options.log)
   getProofKey = assert(options.getProofKey)
   reverseConnection = assert(options.reverseConnection)
   return {
      command=function(cmd, response) safe(command, cmd, response) end
   }
end

return {init=init}
