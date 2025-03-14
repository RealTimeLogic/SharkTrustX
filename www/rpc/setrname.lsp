<?lsp

local function trim(s) return s and s:gsub("^%s*(.-)%s*$", "%1") end
local d=request:data()
local dname,rname=trim(d.dname),trim(d.rname)
local db = require"ZoneDB"
local zoneT=db.znameGetZoneT(request:header"host")
local s = request:session()
local userT = s and s.userT -- Set if authenticated
if userT and zoneT and dname and rname then
   local devT=db.nameGetDeviceT(zoneT.zid, dname)
      if devT then
         if userT.canAccess"power" then
            local ix=rname:find(dname.."$")
            if #rname > 0 and (not ix or ix < 4) then
               response:json{ok=false,err="The name must prefix "..dname}
            end
            db.setDevRname(devT.did,rname)
            local rc=require"RevConnBridge"
            rc.removeDevice(devT.dkey)
            response:json{ok=true}
         end
         response:json{ok=false,err="No access"}
      end
      response:json{ok=false,err="Not found"}
end
response:senderror(404)

?>
