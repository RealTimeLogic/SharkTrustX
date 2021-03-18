local db=[[
PRAGMA foreign_keys = on;
CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO config (key, value) values("version", "1.1");
INSERT INTO config (key, value) values("rootUser","");
INSERT INTO config (key, value) values("rootPwd","");
CREATE TABLE zones(
   zid INTEGER PRIMARY KEY,
   zname TEXT,
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
   name TEXT,
   dkey TEXT,
   localAddr TEXT,
   wanAddr TEXT,
   dns TEXT, -- 'local', 'wan', or 'both'
   info TEXT,
   regTime TEXT,
   accessTime TEXT,
   zid INTEGER,
   FOREIGN KEY (zid) REFERENCES zones(zid));
CREATE TABLE users(
   uid INTEGER PRIMARY KEY,
   email TEXT UNIQUE,
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
]]

local su = require "sqlutil"
local fmt=string.format

local sql11to12=[[
ALTER TABLE zones ADD COLUMN sso INTEGER;
ALTER TABLE zones ADD COLUMN ssocfg TEXT;
ALTER TABLE users ADD COLUMN regTime TEXT;
ALTER TABLE users ADD COLUMN accessTime TEXT;
]]


local function updateDB(conn,quote)
   local ok,err,err2=true 
   local version = su.find(conn,"value FROM config WHERE key='version'")
   if version < "1.1" then
      ok,err,err2 = conn:mexec(sql11to12)
      if ok then
         local now = quote(ba.datetime"NOW":tostring())
         ok,err,err2 = conn:execute(fmt("UPDATE users SET regTime=%s,accessTime=%s",now,now))
      end
      trace("Upgrading DB 1.0 -> 1.1",ok or err)
   end
   if ok then
      conn:execute("UPDATE config SET value=1.1 WHERE key='version'")
   end
   return ok,err,err2
end

local function createDB(conn,quotestr)
   local ok,err,serr=conn:mexec(db)
   if not ok then trace(err,serr) end
   -- Convert old JSON based DB to SQL DB, if any
   io:dofile".lua/Json2DB.lua"(conn,quotestr)
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
   error(string.format("Cannot open zones db: %s",err,err2))
end

return openDB
