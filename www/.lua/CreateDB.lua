local db=[[
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
   zsecret TEXT);
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
   email TEXT,
   pwd TEXT,
   poweruser INTEGER,
   zid INTEGER,
   FOREIGN KEY (zid) REFERENCES zones(zid));
]]


local function updateDB(conn)
   return true
end

local function createDB(conn)
   local ok,err,serr=conn:mexec(db)
   if not ok then trace(err,serr) end
   return ok,err
end


local function openDB()
   local ok
   local su=require"sqlutil"
   local hasDB = su.exist("zones")
   local env,conn=su.open("zones")
   if hasDB then
      ok,err = updateDB(conn)
   else
      ok,err = createDB(conn)
   end
   if ok then return env,conn end
   conn:close()
   env:close()
   error(string.format("Cannot open zones db: %s",err))
end

return openDB
