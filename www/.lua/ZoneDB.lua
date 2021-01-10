local fmt, sbyte, tinsert, tunpack = string.format, string.byte, table.insert, table.unpack
local su = require "sqlutil"
local rcBridge = require "RevConnBridge"

-- 64 byte hex key
local function createHexKey(bytes)
   return ba.rndbs(bytes):gsub(".", function(x) return fmt("%02x", sbyte(x)) end)
end

-- Encapsulation of the connection used exclusively for writing
-- dbExec(sql, noCommit, func)  -- Async DB insert with optional callback
local env, dbExec =
   (function()
   local env, wconn = io:dofile(".lua/CreateDB.lua",_ENV)() -- Requires env:io
   assert(env, fmt("Cannot open zones.db: %s", wconn))
   assert(wconn:execute "PRAGMA foreign_keys = on;")
   assert(wconn:setautocommit "IMMEDIATE")

   local function commit()
      while true do
         local ok, err = wconn:commit "IMMEDIATE"
         if ok then break end
         if err ~= "BUSY" then
            trace("ERROR: commit failed on exclusive connection:", err)
            break
         end
      end
   end

   local function checkExec(sql, ok, err, err2)
      if not ok then
         trace("SQL err:", err2 or err, sql)
      end
   end

   local dbthread = ba.thread.create()
   local function dbExec(sql, noCommit, func)
      tracep(9,sql)
      dbthread:run(
         function()
            if sql then checkExec(sql, wconn:execute(sql)) end
            if not noCommit then commit() end
            if func then func() end
         end
      )
   end
   return env, dbExec
end)()

local quote = env.quotestr

-- Open/close connections used exclusively for reading.
local function openConn()
   local x, conn = su.open(env, "zones")
   return conn
end
local function closeConn(conn)
   conn:close()
end

-- Wraps around  openConn/closeConn and "sqlutil.lua"'s iterator
-- Note, when tab=false: The iterator can at most return one element
local function sqlIter(sql,tab)
   local conn = openConn()
   local next = su.iter(conn, sql, tab)
   return function()
      local t, err = next()
      if t then return t end
      if err then trace("Err:", err, sql) end
      closeConn(conn)
   end
end

-- can return one element, one column or a table
local function dbFind(tab, sql)
   local conn = openConn()
   local x, err = true == tab and su.findt(conn, sql, {}) or su.find(conn, sql)
   if not x and err then trace("Err:", err) end
   closeConn(conn)
   return x
end

-------------------------------  READING  ------------------------------------

local function getZoneKey(zname)
   return dbFind(false, fmt("%s%s%s", "zkey FROM zones WHERE zname=", quote(zname), " COLLATE NOCASE"))
end

local function zidGetZoneT(zid)
   return dbFind(true, fmt("%s%s", "* FROM zones WHERE zid=", zid))
end
local function znameGetZoneT(zname)
   return dbFind(true, fmt("%s%s%s", "* FROM zones WHERE zname=", quote(zname), " COLLATE NOCASE"))
end
local function zkeyGetZoneT(zkey)
   return dbFind(true, fmt("%s%s%s", "* FROM zones WHERE zkey=", quote(zkey), " COLLATE NOCASE"))
end

local function getZoneName(zkey)
   return dbFind(false, fmt("%s%s%s", "zname FROM zones WHERE zkey=", quote(zkey), " COLLATE NOCASE"))
end

local function getZid4Zone(zkey)
   return dbFind(false, fmt("%s%s%s", "zid FROM zones WHERE zkey=", quote(zkey), " COLLATE NOCASE"))
end

-- Returns table with keys 'did,name,dkey,localAddr,wanAddr,dns,info,zid'
local function keyGetDeviceT(dkey)
   return dbFind(true, fmt("%s%s%s", "* FROM devices WHERE dkey=", quote(dkey), " COLLATE NOCASE"))
end

local function nameGetDeviceT(zid, name)
   return dbFind(true, fmt("%s%s and name=%s%s", "* FROM devices WHERE zid=", zid, quote(name), " COLLATE NOCASE"))
end

local function countDevices4Zone(zid)
   return tonumber(dbFind(false, fmt("%s%s", "count(*) FROM devices WHERE zid=", zid)))
end

-- Returns iterator, which returns a table with all of the zone's keys/vals
-- zid can be the zone ID (zid) or the zone key (zkey)
local function getDevices4ZoneT(zid)
   zid = "string" == type(zid) and #zid == 64 and getZid4Zone(zid) or zid
   local sql = fmt("%s%s%s", "* FROM devices WHERE zid=", zid, " ORDER BY wanAddr,name ASC")
   return sqlIter(sql, true)
end

-- Get all devices for zone that are part of the WAN "wanAddr"
--Returns iterator, which returns devT
local function getDevices4Wan(zid, wanAddr)
   local sql = fmt("%s%s%s%s%s", "* FROM devices where wanAddr=", quote(wanAddr), " AND zid=", zid, " ORDER BY name ASC")
   return sqlIter(sql,true)
end

-- Get all devices a regular user has access to
-- Returns:
--   if tab=true: a table where key=did,val=true
--   if not tab: an iterator, which returns a table with all of the zone's keys/vals
local function getDevices4User(uid,tab)
   local sql =
      fmt(
      "%s%s%s%s",
      tab and "devices.did" or "*",
      " FROM devices INNER JOIN UsersDevAccess ON devices.did == UsersDevAccess.did WHERE UsersDevAccess.uid=",
      uid,
      " ORDER BY wanAddr,name ASC"
   )
   if tab then
      local t={}
      local conn = openConn()
      local next = su.iter(conn, sql)
      local did,err = next()
      while did do
         t[did] = true
         did,err = next()
      end
      if err then trace("Err:", err, sql) end
      closeConn(conn)
      return t
   end
   return sqlIter(sql, true)
end


-- Returns iterator, which returns zid,zname,zkey
local function getZonesT()
   local conn = openConn()
   local sql = "zid,zname,zkey FROM zones"
   local next = su.iter(conn, sql)
   return function()
      local zid, zname, zkey = next()
      if zid then return zid, zname, zkey end
      if zname then trace("Err:", zname, sql) end
      closeConn(conn)
   end
end

local function getAutoReg(zid)
   local enabled = dbFind(false, fmt("%s%s", "autoReg FROM zones WHERE zid=",zid))
   return enabled ~= "0"
end


-- Returns table array with all wan addresses for zone ID
local function getWanL(zid)
   local conn = openConn()
   local list = {}
   local sql = fmt("%s%s", "DISTINCT wanAddr FROM devices where zid=", zid)
   for wanAddr in su.iter(conn, sql) do
      tinsert(list, wanAddr)
   end
   closeConn(conn)
   return list
end

-- Returns iterator, which returns uid,email,poweruser
local function getUsers()
   local conn = openConn()
   local sql = "uid,email,poweruser FROM users"
   local next = su.iter(conn, sql)
   return function()
      local uid,email,poweruser = next()
      if uid then return uid,email,poweruser  ~= "0" end
      if email then trace("Err:", email, sql) end
      closeConn(conn)
   end
end


-- Get user info by email addr.
-- Returns userT
local function getUserT(zid, email)
   local uT =
      dbFind(true, fmt("%s%s%s%s%s", "* FROM users WHERE zid=", zid, " AND email=", quote(email), " COLLATE NOCASE"))
   if uT then
      uT.poweruser = uT.poweruser ~= "0"
   end
   return uT
end

-------------------------------  WRITING  ------------------------------------

local function addZone(zname, admEmail, admPwd, func)
   if getZoneKey(zname) then
      trace("Err: zone exists:", zname)
      return
   end
   local zkey
   while true do
      zkey = createHexKey(32)
      if not dbFind(false, fmt("%s%s%s", "zkey FROM zones WHERE zkey=", quote(zkey), " COLLATE NOCASE")) then
         break
      end
   end
   local now = quote(ba.datetime "NOW":tostring())
   dbExec(
      fmt(
         "%s(%s,%s,%s,%s,%s,%s,%s,0)",
         "INSERT INTO zones (zname,regTime,accessTime,admEmail,admPwd,zkey,zsecret,autoReg) VALUES",
         quote(zname),
         now,
         now,
         quote(admEmail),
         quote(admPwd),
         quote(zkey),
         quote(createHexKey(32))
      ),
      false,
      func
   )
   -- Return a simplified zoneT. We just need these values for bindzonedb()
   return {zname = zname, zkey = zkey, zid = 0}
end

local function updateAdmPwd(zid, admPwd)
   dbExec(fmt("UPDATE zones SET admPwd=%s WHERE zid=%s", quote(admPwd), zid))
end

local function updateUSerPwd(zid, email, pwd)
   dbExec(fmt("UPDATE users SET pwd=%s WHERE zid=%s AND email=%s COLLATE NOCASE", quote(pwd), zid, quote(email)))
end

local function setAutoReg(zid, enable)
   dbExec(fmt("UPDATE zones SET autoReg=%d WHERE zid=%s", enable and 1 or 0, zid))
end

local function removeZone(zkey,func)
   local zid = getZid4Zone(zkey)
   if not zid then
      trace("Not found:", zname)
      return
   end
   local devsL={}
   for devT in getDevices4ZoneT(zid) do
      tinsert(devsL, devT)
   end
   for _,devT in ipairs(devsL) do
      dbExec(fmt("%s%s", "DELETE FROM UsersDevAccess WHERE did=", devT.did), true)
      rcBridge.removeDevice(devT.dkey)
   end
   dbExec(fmt("%s%s", "DELETE FROM devices WHERE zid=", zid), true)
   dbExec(fmt("%s%s", "DELETE FROM users WHERE zid=", zid), true)
   dbExec(fmt("%s%s", "DELETE FROM zones WHERE zid=", zid),false,func)
end

local function removeUsers(uidL)
   for _,uid in pairs(uidL) do
      dbExec(fmt("%s%s", "DELETE FROM UsersDevAccess WHERE uid=", uid), true)
      dbExec(fmt("%s%s", "DELETE FROM Users WHERE uid=", uid), true)
   end
   dbExec() -- Commit
end


local function addDevice(zkey, name, localAddr, wanAddr, dns, info, func)
   local zid = getZid4Zone(zkey)
   if not zid then
      trace("zkey not found:", zkey)
      return
   end
   if dbFind(false, fmt("%s%s AND name=%s%s", "dkey FROM devices WHERE zid=", zid, quote(name), " COLLATE NOCASE")) then
      trace("Err: device exists:", name)
      return
   end

   local dkey
   while true do
      dkey = createHexKey(10)
      if not dbFind(false, fmt("%s%s%s", "dkey FROM devices WHERE dkey=", quote(dkey), " COLLATE NOCASE")) then
         break
      end
   end
   local now = quote(ba.datetime"NOW":tostring())
   dbExec(
      fmt(
         "%s(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
         "INSERT INTO devices (name,dkey,localAddr,wanAddr,dns,info,regTime,accessTime,zid) VALUES",
         quote(name),
         quote(dkey),
         quote(localAddr),
         quote(wanAddr),
         quote(dns),
         quote(info),
         now,
         now,
         zid
      ),
      false,
      func
   )
   return dkey
end

local function updateAddress4Device(dkey, localAddr, wanAddr, dns, func)
   dbExec(
      fmt(
         "UPDATE devices SET localAddr=%s, wanAddr=%s, dns=%s, accessTime=%s WHERE dkey=%s",
         quote(localAddr),
         quote(wanAddr),
         quote(dns),
         quote(ba.datetime "NOW":tostring()),
         quote(dkey)
      ),
      false,
      func
   )
end

local function updateTime4Device(dkey)
   dbExec(fmt("UPDATE devices SET accessTime=%s WHERE dkey=%s", quote(ba.datetime "NOW":tostring()), quote(dkey)))
end

local function removeDevice(dkey, func)
   local t = keyGetDeviceT(dkey)
   if t then
      dbExec(fmt("%s%s", "DELETE FROM UsersDevAccess WHERE did=", t.did), true)
      dbExec(fmt("%s%s%s", "DELETE FROM devices WHERE did=", t.did, " COLLATE NOCASE"), false, func)
      rcBridge.removeDevice(dkey)
   else
      trace("Not found", dkey)
   end
end

local function addUser(zid, email, pwd, poweruser)
   dbExec(
      fmt(
         "%s(%s,%s,%d,%s)",
         "INSERT INTO users (email,pwd,poweruser,zid) VALUES",
         quote(email),
         quote(pwd),
         poweruser and 1 or 0,
         zid
      )
   )
end

local function setPoweruser(uid, poweruser)
   dbExec(fmt("UPDATE users SET poweruser=%d WHERE uid=%s", poweruser and 1 or 0, uid))
end

-- Create an entry in UserDevAccess if the entry does not exist 
local function createUserDevAccess(uid,did,noCommit)
      -- Execute UPSERT
      dbExec(
         fmt(
            "%s(%s,%s)%s",
            "INSERT INTO UsersDevAccess (did,uid) VALUES",
            did,
            uid,
            "ON CONFLICT (did,uid) DO NOTHING"
         ),
         noCommit
      )
end

-- Auto set user access for all devices part of "wanAddr".
-- This function is called when user logs in.
local function setUserAccess4Wan(zid, uid, wanAddr)
   for devT in getDevices4Wan(zid, wanAddr) do
      createUserDevAccess(uid,devT.did, true)
   end
   dbExec() -- Commit
end

-- Create or delete an entry in UsersDevAccess
local function setDevAccess4User(uid,did,enable)
   if enable then
      createUserDevAccess(uid,did)
   else
      dbExec(fmt("%s uid=%s and did=%s", "DELETE FROM UsersDevAccess WHERE", uid,did))
   end
end

return {
   addDevice = addDevice, -- (zkey, name, localAddr, wanAddr, dns, info, func)
   addUser = addUser, -- (zid, email, pwd, poweruser)
   addZone = addZone, -- (zname, admEmail, admPwd, func)
   countDevices4Zone = countDevices4Zone, -- (zid)
   getAutoReg=getAutoReg, -- (zid)
   getDevices4User=getDevices4User, -- (uid)
   getDevices4Wan = getDevices4Wan, -- (zid, wanAddr)
   getDevices4ZoneT = getDevices4ZoneT, -- (zid)
   getUserT = getUserT, -- (zid, email)
   getUsers=getUsers, -- ()
   getWanL = getWanL, -- (zid)
   getZid4Zone = getZid4Zone, -- (zkey)
   getZoneKey = getZoneKey, -- (zname)
   getZoneName = getZoneName, -- (zkey)
   getZonesT = getZonesT, -- ()
   keyGetDeviceT = keyGetDeviceT, -- (dkey)
   nameGetDeviceT = nameGetDeviceT, -- (zid, name)
   removeDevice = removeDevice, -- (dkey, func)
   removeUsers=removeUsers, -- (uidL)
   removeZone = removeZone, -- (zkey)
   setAutoReg=setAutoReg, -- (zid, enable)
   setDevAccess4User=setDevAccess4User, -- (uid,did,enable)
   setPoweruser=setPoweruser, -- (uid, poweruser)
   setUserAccess4Wan = setUserAccess4Wan, -- (zid, uid, wanAddr)
   updateAddress4Device = updateAddress4Device, -- (dkey, localAddr, wanAddr, dns, func)
   updateAdmPwd = updateAdmPwd, -- (zid, admPwd)
   updateTime4Device = updateTime4Device, -- (dkey)
   updateUSerPwd = updateUSerPwd, -- (zid, email, pwd)
   zidGetZoneT = zidGetZoneT, -- (zid)
   zkeyGetZoneT = zkeyGetZoneT, -- (zkey)
   znameGetZoneT = znameGetZoneT -- (zname)
}
