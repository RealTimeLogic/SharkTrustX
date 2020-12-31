-- Reverse Connection Bridge

local fmt=string.format

-- devicesT: All devices:  key=dkey, val is a table with:
--   activeCons - Active connections (client socks conns)
--   dz - RevConn's Device-Zone name. FQN is: dz.zname
--   lastActiveTime - When last revcon was established
--   idleSocksT - table storing idle device cons: key=socket, val=function(sock)
--   zname - zone name
-- Note: a dkey is unique across all zones
local devicesT={}

-- The devices' sub domain (dz) is rotated this often for security reasons
local secretsExpTimeSpan = {hours = 12}

-- Provided by the .preload script and set via the init() function
local setRecord -- function(zname, recordName)
local removeRecord -- function(zname, recordName)

-- Two cosocket instances per connection, one for server and one for client
local function connectionBridge(source,deviceT,sink)
   local isServer = not sink and true or false
   local peer = source:peername()
   if not sink then -- Idle device
      deviceT.idleSocksT[source]=function(sock) sink=sock end
   end
   local data,err = source:read()
   if not data then
      source:close()
      if sink then sink:close() end
      deviceT.idleSocksT[source]=nil
      return
   end
   if isServer then
      deviceT.lastActiveTime=ba.datetime"NOW"
      deviceT.activeCons = deviceT.activeCons + 1
   end
   while data do
      if not sink:write(data,err) then break end
      data,err = source:read()
   end
   if isServer then
      deviceT.activeCons = deviceT.activeCons - 1
      deviceT.idleSocksT[source]=nil
   end
   source:close()
   sink:close()
end

local function createSecret()
   local sb=string.byte
   return ba.rndbs(10):gsub(".",function(x) return fmt("%02x",sb(x)) end)
end

-- Set up a new idle (pending) device reverse connection
local function newDevice(zname,dkey,sock)
   if not sock then return end
   dkey=dkey:lower()
   local deviceT = devicesT[dkey]
   if not deviceT then
      deviceT = {
         idleSocksT={},
         zname=zname,
         dz=createSecret()..dkey,
         activeCons=0,
         lastActiveTime=ba.datetime"NOW",
         secretExpTime=ba.datetime"NOW" + secretsExpTimeSpan
      }
      devicesT[dkey] = deviceT
      setRecord(zname, deviceT.dz)
   end
   tracep(9,"Device",fmt("https://%s.%s",deviceT.dz,zname), sock)
   sock:setoption("keepalive",true,240,240)
   sock:event(connectionBridge,"s",deviceT)
end


local function removeDevice(dkey)
   local deviceT = devicesT[dkey]
   if deviceT then
      devicesT[dkey]=nil
      for sock in pairs(deviceT.idleSocksT) do
         sock:close()
      end
      removeRecord(deviceT.zname, deviceT.dz)
   end
end


local function connectClient(deviceT, deviceSock, cmd)
   -- We must recreate the HTTP header for new requests (New socket connections)
   local method=cmd:method()
   local header=cmd:header()
   if method == "POST" and header["Content-Type"] == "application/x-www-form-urlencoded" then
      -- Embedded post body as query in URL via response:encoderedirecturl
      header["Content-Length"] ="0"
   end
   local reqHeader = {
      fmt("%s %s HTTP/1.1",
          method,
          cmd:encoderedirecturl(cmd:uri(), true))
   }
   for k,v in pairs(header) do
      table.insert(reqHeader,fmt("%s: %s",k,v))
   end
   table.insert(reqHeader,"\r\n")
   local clientSock,data=ba.socket.req2sock(cmd, true)
   --local clientSock,data=ba.socket.req2sock(cmd)
   if clientSock then
      local func=deviceT.idleSocksT[deviceSock]
      deviceT.idleSocksT[deviceSock]=nil
      func(clientSock)
      deviceSock:write(table.concat(reqHeader,"\r\n"))
      if data then deviceSock:write(data) end
      clientSock:event(connectionBridge,"s", deviceT,deviceSock)
   end
end

-- Designed for LSP pages and may sleep for up to 50*20 milliseconds
-- The code also includes logic for preventing a user from guessing the sub-domain (dz)
local blockedIpT={}
local function newClient(cmd,dz,zone)
   local peer = cmd:peername()
   if blockedIpT[peer] then
      cmd:senderror(503)
      return
   end
   dz=dz:lower()
   local dkey=dz:sub(21)
   local deviceT = devicesT[dkey]
   if deviceT and deviceT.dz == dz then
      for i=1,50 do
         local sock = next(deviceT.idleSocksT)
         if sock then
            connectClient(deviceT, sock, cmd)
            return true
         end
         ba.sleep(20)
      end
      -- Giving up. No available reverse connection.
      tracep(9,"Giving up")
      cmd:setheader("Retry-After", "3")
      cmd:setheader("Location",cmd:encoderedirecturl(cmd:url(),true,true))
      cmd:setcontentlength(0)
      cmd:setstatus(302)
      return false
   end
   -- domain not found
   -- Enable logic for preventing a user from guessing the sub-domain
   cmd=cmd:deferred()
   cmd:setstatus(302)
   cmd:setheader("Location","https://"..zone)
   blockedIpT[peer]=true
   ba.timer(function() blockedIpT[peer]=nil cmd:setcontentlength(0) cmd:close() end):set(5000,true)
   return false
end

-- For security reasons, create a new Device-Zone name when idle for more than 12 hours
local function terminateIdleDevs()
   local now = ba.datetime"NOW"
   for dkey,deviceT in pairs(devicesT) do
      if deviceT.activeCons == 0 and deviceT.secretExpTime < now then
         removeRecord(deviceT.zname, deviceT.dz, true)
         deviceT.dz=createSecret()..dkey
         deviceT.secretExpTime = now + secretsExpTimeSpan
         setRecord(deviceT.zname, deviceT.dz)
      end
   end
   return true -- Keep running interval timer
end
ba.timer(terminateIdleDevs):set(60*60*1000,true)

-- Returns dz, active=(true/false), lastActiveTime, activeCons
local function getDevInfo(dkey)
   local deviceT = devicesT[dkey:lower()]
   if deviceT then
      ba.json.encode(deviceT)
      return deviceT.dz,(next(deviceT.idleSocksT) and true or false),deviceT.lastActiveTime,deviceT.activeCons
   end
end


local function init(initT)
   setRecord=initT.setRec
   removeRecord=initT.removeRec
end
   
return {
   newDevice=newDevice, -- (zname,dkey,sock)
   removeDevice=removeDevice, -- (dkey)
   newClient=newClient, -- (cmd,dz,zone)
   getDevInfo=getDevInfo,
   init=init, -- (initT)
}
