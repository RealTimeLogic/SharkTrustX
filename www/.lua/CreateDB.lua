local db=[[
PRAGMA foreign_keys = on;
CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO config (key, value) values("version", "1.0");
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
   autoReg INTEGER);
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


local function updateDB(conn)
   return true
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
      ok,err,err2 = updateDB(conn)
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
