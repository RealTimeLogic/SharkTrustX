local db=[[
PRAGMA foreign_keys = on;
CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO config (key, value) values("version", "1.5");
INSERT INTO config (key, value) values("rootUser","");
INSERT INTO config (key, value) values("rootPwd","");
CREATE TABLE zones(
   zid INTEGER PRIMARY KEY,
   zname TEXT,
   rname TEXT, -- reverse connection sub domain name prefix; prefix for devices.rname
   regTime TEXT,
   accessTime TEXT,
   admPwd TEXT,
   admEmail TEXT,
   zkey TEXT,
   zsecret TEXT,
   autoReg INTEGER, -- boolean enabled/disabled
   sso INTEGER, -- boolean Single Sign On enabled/disabled
   ssocfg TEXT); -- JSON Single Sign On config
CREATE TABLE devices(
   did INTEGER PRIMARY KEY,
   name TEXT, -- sub domain name
   rname TEXT, -- reverse connection sub domain name
   dkey TEXT,
   localAddr TEXT,
   wanAddr TEXT,
   dns TEXT, -- 'local', 'wan', or 'both'
   info TEXT,
   v2credHash TEXT,
   v2credCreated TEXT,
   regTime TEXT,
   accessTime TEXT,
   zid INTEGER,
   FOREIGN KEY (zid) REFERENCES zones(zid));
CREATE TABLE users(
   uid INTEGER PRIMARY KEY,
   email TEXT,
   pwd TEXT,
   regTime TEXT,
   accessTime TEXT,
   poweruser INTEGER,
   zid INTEGER,
   FOREIGN KEY (zid) REFERENCES zones(zid));
CREATE TABLE UsersDevAccess(
   did INTEGER,
   uid INTEGER,
   FOREIGN KEY (did) REFERENCES devices(did),
   FOREIGN KEY (uid) REFERENCES users(uid));

CREATE UNIQUE INDEX UsersDevAccessIx ON UsersDevAccess (did, uid);
CREATE UNIQUE INDEX DevicesV2CredHashIx ON devices (v2credHash);
CREATE UNIQUE INDEX DevicesZoneNameIx ON devices (zid, name COLLATE NOCASE);
]]

local su = require "sqlutil"
local fmt=string.format

local s12to13=[[
ALTER TABLE zones ADD COLUMN rname TEXT;
ALTER TABLE devices ADD COLUMN rname TEXT;
]]

local s13to14=[[
ALTER TABLE devices ADD COLUMN v2credHash TEXT;
ALTER TABLE devices ADD COLUMN v2credCreated TEXT;
CREATE UNIQUE INDEX DevicesV2CredHashIx ON devices (v2credHash);
]]

local s14to15=[[
CREATE UNIQUE INDEX DevicesZoneNameIx ON devices (zid, name COLLATE NOCASE);
]]

-- remove UNIQUE constraint on users.email
local s11to12=[[
CREATE TABLE newusers(uid INTEGER PRIMARY KEY,email TEXT,pwd TEXT,regTime TEXT,accessTime TEXT,poweruser INTEGER,zid INTEGER,FOREIGN KEY (zid) REFERENCES zones(zid));
INSERT INTO newusers(uid,email,pwd,regTime,accessTime,poweruser,zid) SELECT uid,email,pwd,regTime,accessTime,poweruser,zid FROM users;
DROP TABLE users;
ALTER TABLE newusers RENAME TO users;
]]
local function updateDB(conn,quote)
   local version = su.find(conn,"value FROM config WHERE key='version'")
   local function versionNumber(value)
      if type(value) ~= "string" then return nil end
      local major,minor=value:match("^(%d+)%.(%d+)$")
      return major and tonumber(major) * 1000 + tonumber(minor)
   end
   local current=versionNumber(version)
   assert(current and current >= versionNumber"1.1", "DB too old")
   assert(current <= versionNumber"1.5", "DB version is newer than this portal")

   local migrations={
      {from="1.1", to="1.2", sql=s11to12},
      {from="1.2", to="1.3", sql=s12to13},
      {from="1.3", to="1.4", sql=s13to14},
      {from="1.4", to="1.5", sql=s14to15}
   }
   for _,migration in ipairs(migrations) do
      if current < versionNumber(migration.to) then
         local ok,err,err2=conn:mexec(migration.sql)
         trace(fmt("Upgrading DB %s -> %s",migration.from,migration.to),ok or (err2 or err))
         if not ok then return ok,err,err2 end
         ok,err,err2=conn:execute(fmt("UPDATE config SET value='%s' WHERE key='version'",migration.to))
         if not ok then return ok,err,err2 end
         current=versionNumber(migration.to)
      end
   end
   return true
end

local function createDB(conn,quotestr)
   local ok,err,serr=conn:mexec(db)
   if not ok then trace(err,serr) end
   return ok,err
end


local function openDB()
   local ok,err,err2
   local su=require"sqlutil"
   local hasDB = su.exist("zones")
   local env,conn=su.open("zones")
   if hasDB then
      ok,err,err2 = updateDB(conn,env.quotestr)
   else
      ok,err,err2 = createDB(conn,env.quotestr)
   end
   if ok then
      conn:setbusytimeout(10000)
      return env,conn
   end
   conn:close()
   env:close()
   error(string.format("Cannot open zones db: %s %s",err,err2 or ""))
end

return openDB
