<?lsp

-- Remove device if zone admin.

local dname=request:data"name"
local zname=request:header"host"
local db = require"ZoneDB"
local zoneT=db.znameGetZoneT(zname)
if request:user() and zoneT and dname then
      local devT=db.nameGetDeviceT(zoneT.zid, dname)
      if devT then
         local s = request:session()
         local user = s.userT and s.userT.type
         if user ~="admin" and user ~="root" then
            response:json{ok=false}
         else
            app.deleteDevice(zoneT, devT.dkey)
            response:json{ok=true}
         end
      end
end
response:senderror(404)

?>
