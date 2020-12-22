local fmt,sbyte,tinsert,tunpack = string.format,string.byte,table.insert,table.unpack
local su=require"sqlutil"

-- 64 byte hex key
local function createHexKey(bytes)
   return ba.rndbs(bytes):gsub(".",function(x) return fmt("%02X",sbyte(x)) end)
end

local env,dbExec,getWConn = (function()
   local env, wconn = io:dofile".lua/CreateDB.lua"()
   assert(env, fmt("Cannot open zones.db: %s", wconn))
   assert(wconn:execute"PRAGMA foreign_keys = on;")
   assert(wconn:setautocommit "IMMEDIATE")

   local function commit()
      while true do
         local ok, err = wconn:commit"IMMEDIATE"
         if ok then break end
         if err ~= "BUSY" then
            trace("ERROR: commit failed on exclusive connection:", err)
            break
         end
      end
   end
  
   local function checkExec(sql,ok,err,err2)
      if not ok then trace("SQL err:",err2 or err, sql) end
   end
    
   local dbthread = ba.thread.create()
   local function dbExec(sql,noCommit,func)
      dbthread:run(function()
         checkExec(sql,wconn:execute(sql))
         if not noCommit then commit() end
         if func then func() end
      end)
   end
   return env,dbExec,function() return wconn end
end)()

local quote=env.quotestr

local function openConn()
   local x,conn = su.open(env, "zones")
   return conn
end

local function closeConn(conn)
   conn:close()
end

-------------------------------  READING  ------------------------------------

--  ret tab, key=zone,val=zkey
local function getZonesT()
   local su=require"sqlutil"
   local zT={}
   local function execute(cur)
      local zname,zkey = cur:fetch()
      while key do
         zT[zname]=zkey
         zname,zkey = cur:fetch()
      end
   end
   local conn = openConn()
   su.select(conn, "zname,zkey FROM zones", execute)
end

-- can return one element, one column or a table
local function dbFind(tab,sql)
   local conn = openConn()
   local x,err = true==tab and su.findt(conn,sql,{}) or su.find(conn,sql)
   if not x and err then trace("Err:",err) end
   closeConn(conn)
   return x
end

local function getZoneKey(zname)
   return dbFind(false,fmt("zkey FROM zones WHERE zname=%s",quote(zname)))
end

local function zidGetZoneT(zid)
   return dbFind(true,fmt("%s%s","* FROM zones WHERE zid=",zid))
end
local function znameGetZoneT(zname)
   return dbFind(true,fmt("%s%s","* FROM zones WHERE zname=",quote(zname)))
end
local function zkeyGetZoneT(zkey)
   return dbFind(true,fmt("%s%s","* FROM zones WHERE zkey=",quote(zkey)))
end

local function getZoneName(zkey)
   return dbFind(false,fmt("zname FROM zones WHERE zkey=%s",quote(zkey)))
end

local function getZid4Zone(zkey)
   return dbFind(false,fmt("zid FROM zones WHERE zkey=%s",quote(zkey)))
end

-- Returns table with keys 'did,name,dkey,localAddr,wanAddr,dns,info,zid'
local function keyGetDeviceT(dkey)
   return dbFind(true,fmt("%s%s","* FROM devices WHERE dkey=",quote(dkey)))
end

local function nameGetDeviceT(zid,name)
   return dbFind(true,fmt("%s%s and name=%s","* FROM devices WHERE zid=",zid,quote(name)))
end

-- Returns iterator, which returns a table with all of the zone's keys/vals
local function getDevices4ZoneT(zid)
   zid = "string"==type(zid) and #zid == 64 and getZid4Zone(zid) or zid
   local conn = openConn()
   local sql=fmt("%s%s","* FROM devices WHERE zid=",zid)
   local next = su.iter(conn,sql,true)
   return function()
      local t,err = next()
      if t then return t end
      if err then trace("Err:",err,sql) end
      closeConn(conn)
   end
end

local function countDevices4Zone(zid)
   return tonumber(dbFind(false,fmt("%s%s","count(*) FROM devices WHERE zid=",zid)))
end

-- Returns iterator, which returns zid,zname,zkey
local function getZonesT()
   local conn = openConn()
   local sql="zid,zname,zkey FROM zones"
   local next = su.iter(conn,sql)
   return function()
      local zid,zname,zkey = next()
      if zid then return zid,zname,zkey end
      if zname then trace("Err:",zname,sql) end
      closeConn(conn)
   end
end

local function getWanL(zid)
   local conn = openConn()
   local list={}
   local sql=fmt("%s%s)","DISTINCT wanAddr FROM devices where zid=(SELECT zid FROM zones WHERE zid=",zid)
   for wanAddr in su.iter(conn,sql) do
      tinsert(list, wanAddr)
   end
   closeConn(conn)
   return list
end

--Returns iterator, which returns devT
local function getDevices4Wan(zid,wanAddr)
   local conn = openConn()
   local sql = fmt("%s%s%s%s","* FROM devices where wanAddr=",quote(wanAddr)," AND zid=",zid)
   local next = su.iter(conn,sql,true)
   return function()
      local t,err = next()
      if t then return t end
      if err then trace("Err:",err,sql) end
      closeConn(conn)
   end
end



-------------------------------  WRITING  ------------------------------------

local function addZone(zname, admEmail, admPwd,func)
   if getZoneKey(zname) then
      trace("Err: zone exists:",zname)
      return
   end
   local zkey
   while true do
      zkey = createHexKey(32)
      if not dbFind(false,fmt("%s%s","zkey FROM zones WHERE zkey=",quote(zkey))) then break end
   end
   local now=quote(ba.datetime"NOW":tostring())
   dbExec(fmt(
      "%s(%s,%s,%s,%s,%s,%s,%s)",
      "INSERT INTO zones (zname,regTime,accessTime,admEmail,admPwd,zkey,zsecret) VALUES",
      quote(zname),now,now,quote(admEmail),quote(admPwd),
      quote(zkey),quote(createHexKey(32))),false,func)
   -- Return a simplified zoneT. We just need these values for bindzonedb()
   return {zname=zname,zkey=zkey,zid=0}
end

local function updateAdmPwd(zid, admPwd)
   dbExec(fmt("UPDATE zones SET admPwd=%s WHERE zid=%s",quote(admPwd),zid))
end

local function removeZone(zkey)
   local zid = getZid4Zone(zkey)
   if not zid then trace("Not found:",zname) return end
   dbExec(fmt("%s%s","DELETE FROM devices WHERE zid=",zid),true)
   dbExec(fmt("%s%s","DELETE FROM users WHERE zid=",zid),true)
   dbExec(fmt("%s%s","DELETE FROM zones WHERE zid=",zid))
end

local function addDevice(zkey,name,localAddr,wanAddr,dns,info,func)
   local zid = getZid4Zone(zkey)
   if not zid then trace("zkey not found:",zkey) return end
   if dbFind(false,fmt("%s%s AND name=%s","dkey FROM devices WHERE zid=",zid,quote(name))) then
      trace("Err: device exists:",name)
      return
   end

   local dkey
   while true do
      dkey = createHexKey(10)
      if not dbFind(false,fmt("%s%s","dkey FROM devices WHERE dkey=",quote(dkey))) then break end
   end
   local now=quote(ba.datetime"NOW":tostring())
   dbExec(fmt("%s(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
      "INSERT INTO devices (name,dkey,localAddr,wanAddr,dns,info,regTime,accessTime,zid) VALUES",
      quote(name),quote(dkey),quote(localAddr),quote(wanAddr),quote(dns),quote(info),now,now,zid),false,func)
   return dkey
end

local function updateAddress4Device(dkey,localAddr,wanAddr,dns,func)
   dbExec(fmt("UPDATE devices SET localAddr=%s, wanAddr=%s, dns=%s, accessTime=%s WHERE dkey=%s",
      quote(localAddr),quote(wanAddr),quote(dns),quote(ba.datetime"NOW":tostring()),quote(dkey)),false,func)
end

local function updateTime4Device(dkey)
   dbExec(fmt("UPDATE devices SET accessTime=%s WHERE dkey=%s", quote(ba.datetime"NOW":tostring()),quote(dkey)))
end

local function removeDevice(dkey,func)
   local t = keyGetDeviceT(dkey)
   if t then
      dbExec(fmt("%s%s","DELETE FROM devices WHERE dkey=",quote(dkey)),false,func)
   else
      trace("Not found",dkey)
   end
end


return {
   addDevice=addDevice,
   getWanL=getWanL,
   addZone=addZone,
   getZonesT=getZonesT,
   keyGetDeviceT=keyGetDeviceT,
   nameGetDeviceT=nameGetDeviceT,
   updateAddress4Device=updateAddress4Device,
   updateTime4Device=updateTime4Device,
   updateAdmPwd=updateAdmPwd,
   removeDevice=removeDevice,
   getZid4Zone=getZid4Zone,
   getZoneKey=getZoneKey,
   getZoneName=getZoneName,
   zidGetZoneT=zidGetZoneT,
   znameGetZoneT=znameGetZoneT,
   zkeyGetZoneT=zkeyGetZoneT,
   removeZone=removeZone,
   getDevices4ZoneT=getDevices4ZoneT,
   getDevices4Wan=getDevices4Wan,
   countDevices4Zone=countDevices4Zone,
   getWConn=function() return getWConn(),quote end -- Used by Json2DB.lua
}

