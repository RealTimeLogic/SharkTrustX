-- Reverse Connection Bridge

local fmt=string.format
local maxPending,pendingTimeout=16,15000

-- devicesT: All devices:  key=dkey, val is a table with:
--   activeCons - Active connections (client socks conns)
--   dz - RevConn's Device-Zone name. FQN is: dz.zname
--   lastActiveTime - When last revcon was established
--   idleSocksT - table storing idle device cons: key=socket, val=function(sock)
--   pending - FIFO browser connections waiting for the next device socket
--   zname - zone name
-- Note: a dkey is unique across all zones
local devicesT={}

-- Same as above, but the key is the device zone name 'dz'
local dzT={}

-- The devices' sub domain (dz) is rotated this often for security reasons
local secretsExpTimeSpan = {hours = 36}

-- Provided by the .preload script and set via the init() function
local setRecord -- function(zname, recordName)
local removeRecord -- function(zname, recordName)

-- Two cosocket instances per connection, one for server and one for client
local function connectionBridge(source,deviceT,sink,deviceSide)
   if deviceSide then
      deviceT.lastActiveTime=ba.datetime"NOW"
   end
   if deviceSide and not sink then -- Idle device
      deviceT.idleSocksT[source]=function(sock) sink=sock end
   end
   local data,err = source:read()
   if not data then
      source:close()
      if sink then sink:close() end
      deviceT.idleSocksT[source]=nil
      return
   end
   if deviceSide then
      deviceT.activeCons = deviceT.activeCons + 1
   end
   while data do
      if not sink:write(data,err) then break end
      data,err = source:read()
   end
   if deviceSide then
      deviceT.activeCons = deviceT.activeCons - 1
      deviceT.idleSocksT[source]=nil
      if deviceT.activeCons == 0 then
         deviceT.secretExpTime = ba.datetime"NOW" + secretsExpTimeSpan
      end
   end
   source:close()
   sink:close()
end

local function unavailable(client)
   if client.timer then client.timer:cancel() end
   client.sock:write("HTTP/1.1 503 Service Unavailable\r\nRetry-After: 3\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
   client.sock:close()
end

local function connectClient(deviceT,deviceSock,client,idle)
   if client.timer then client.timer:cancel() client.timer=nil end
   deviceT.lastActiveTime=ba.datetime"NOW"
   if idle then
      local setSink=deviceT.idleSocksT[deviceSock]
      deviceT.idleSocksT[deviceSock]=nil
      setSink(client.sock)
   else
      deviceSock:event(connectionBridge,"s",deviceT,client.sock,true)
   end
   deviceSock:write(client.header)
   if client.data then deviceSock:write(client.data) end
   client.sock:event(connectionBridge,"s",deviceT,deviceSock)
end

local function createSecret()
   local sb=string.byte
   return ba.rndbs(16):gsub(".",function(x) return fmt("%02x",sb(x)) end)
end

-- Set up a new idle (pending) device reverse connection
local function newDevice(zname,rname,dkey,sock)
   if not sock then return end
   if rname and 0==#rname then rname=nil end
   dkey=dkey:lower()
   local deviceT = devicesT[dkey]
   if not deviceT then
      deviceT = {
         idleSocksT={},
         pending={},
         zname=zname,
         rname=rname,
         dz=rname or createSecret(),
         activeCons=0,
         lastActiveTime=ba.datetime"NOW",
         secretExpTime = ba.datetime"MAX"
      }
      devicesT[dkey] = deviceT
      dzT[deviceT.dz] = deviceT
      setRecord(zname, deviceT.dz)
   end
   -- Generated reverse names are credentials and must not be logged.
   tracep(9,"Device reverse connection",zname,sock)
   deviceT.lastActiveTime=ba.datetime"NOW"
   sock:setoption("keepalive",true,240,240)
   local client=table.remove(deviceT.pending,1)
   if client then connectClient(deviceT,sock,client) else
      sock:event(connectionBridge,"s",deviceT,nil,true)
   end
end


local function removeDevice(dkey)
   local deviceT = devicesT[dkey]
   if deviceT then
      devicesT[dkey]=nil
      dzT[deviceT.dz]=nil
      for sock in pairs(deviceT.idleSocksT) do
         sock:close()
      end
      for _,client in ipairs(deviceT.pending) do unavailable(client) end
      removeRecord(deviceT.zname, deviceT.dz)
   end
end


local function clientRequest(cmd)
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
   local sock,data=ba.socket.req2sock(cmd,true)
   return sock and {sock=sock,data=data,header=table.concat(reqHeader,"\r\n")}
end

-- The code also includes logic for preventing a user from guessing the sub-domain (dz)
local blockedIpT={}
local function newClient(cmd,dz,zone)
   local peer = cmd:peername()
   if blockedIpT[peer] then
      cmd:senderror(503)
      return
   end
   local deviceT = dzT[dz:lower()]
   if deviceT then
      local deviceSock=next(deviceT.idleSocksT)
      if not deviceSock and ((deviceT.lastActiveTime + {secs=40}) < ba.datetime"NOW" or
         #deviceT.pending >= maxPending) then
         cmd:senderror(503)
         return false
      end
      local client=clientRequest(cmd)
      if not client then return false end
      if deviceSock then connectClient(deviceT,deviceSock,client,true) else
         table.insert(deviceT.pending,client)
         client.timer=ba.timer(function()
            for i,item in ipairs(deviceT.pending) do
               if item == client then table.remove(deviceT.pending,i) unavailable(client) break end
            end
         end)
         client.timer:set(pendingTimeout,true)
      end
      return true
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

-- For security reasons, create a new Device-Zone name when idle for more than 'secretsExpTimeSpan'.
-- However, we do not change the zone name if we have not had any client connections.
local function terminateIdleDevs()
   local now = ba.datetime"NOW"
   for dkey,deviceT in pairs(devicesT) do
      if deviceT.secretExpTime < now and not deviceT.rname then
         removeRecord(deviceT.zname, deviceT.dz, true)
         dzT[deviceT.dz]=nil
         deviceT.dz=createSecret()
         dzT[deviceT.dz]=deviceT
         deviceT.secretExpTime = ba.datetime"MAX"
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
      local active=next(deviceT.idleSocksT) ~= nil or deviceT.activeCons > 0
      return deviceT.dz,active,deviceT.lastActiveTime,deviceT.activeCons
   end
end


local function init(initT)
   setRecord=initT.setRec
   removeRecord=initT.removeRec
end
   
return {
   newDevice=newDevice, -- (zname,rname,dkey,sock)
   removeDevice=removeDevice, -- (dkey)
   newClient=newClient, -- (cmd,dz,zone)
   getDevInfo=getDevInfo,
   getDz=function(dz) return dz and dzT[dz] end,
   init=init, -- (initT)
}
