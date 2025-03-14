<?lsp

-- Remove device if zone admin.

local dname=request:data"name"
local db = require"ZoneDB"
local zoneT=db.znameGetZoneT(request:header"host")
local s = request:session()
local userT = s and s.userT -- Set if authenticated
if userT and zoneT and dname then
   local devT=db.nameGetDeviceT(zoneT.zid, dname)
      if devT then
         if userT.canAccess"power" then
            app.deleteDevice(zoneT, devT.dkey)
            response:json{ok=true}
         end
         response:json{ok=false,err="No access"}
      end
      response:json{ok=false,err="Not found"}
end
response:senderror(404)

?>
