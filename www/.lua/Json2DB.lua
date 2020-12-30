local fmt = string.format

local function convert(conn,q)
   local io=ba.mkio(ba.openio"home","data")
   trace(io,conn,q)
   if not io then
      return
   end
   local rw = require "rwfile"
   local zones = rw.json(io, "zones.json")
   if zones then
      io:remove"zones.json"
      local su = require "sqlutil"
      local now = q(ba.datetime "NOW":tostring())
      for zone, zkey in pairs(zones) do
         local fname="z." .. zkey .. ".json"
         local zT = rw.json(io, fname)
         if zT then
            io:remove(fname)
            io:remove("w." .. zkey .. ".json")
            local sbyte=string.byte
            secret =
               zT.secret or
               ba.rndbs(32):gsub(
                  ".",
                  function(x)
                     return fmt("%02X", sbyte(x))
                  end
               )
            conn:execute(
               fmt(
                  "%s(%s,%s,%s,%s,%s,%s,%s,0)",
                  "INSERT INTO zones (zname,regTime,accessTime,admEmail,admPwd,zkey,zsecret,autoReg) VALUES",
                  q(zT.zname),
                  q(ba.datetime(tonumber(zT.rtime)):tostring()),
                  now,
                  q(zT.uname),
                  q(zT.ha1),
                  q(zkey),
                  q(secret)
               )
            )
            local zid = conn:lastid()
            for name, dkey in pairs(zT.devices) do
               local fname="d." .. dkey .. ".json"
               local dT = rw.json(io, fname)
               if dT then
                  io:remove(fname)
                  conn:execute(
                     fmt(
                        "%s(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                        "INSERT INTO devices (name,dkey,localAddr,wanAddr,dns,info,regTime,accessTime,zid) VALUES",
                        q(dT.name),
                        q(dkey),
                        q(dT.ip),
                        q(dT.wan),
                        q(dT.dns),
                        q(dT.info),
                        q(ba.datetime(tonumber(dT.atime)):tostring()),
                        now,
                        zid
                     )
                  )
               end
            end
         end
      end
      conn:commit"IMMEDIATE"
   end
end

return convert
