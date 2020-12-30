<?lsp

-- Remove device if zone admin.

local s = request:session()
local user = s.userT and s.userT.type
trace(user)
if user ~="admin" then
   response:json{ok=false}
end

local dname=request:data"name"
local zname=request:header"host"
local db = require"ZoneDB"
local zoneT=db.znameGetZoneT(zname)
if zoneT and dname then
      local devT=db.nameGetDeviceT(zoneT.zid, dname)
      if devT then
         app.deleteDevice(zoneT, devT.dkey)
         response:json{ok=true}
      end
end
response:senderror(404)

?>
