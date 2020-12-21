<?lsp

local dname=request:data"name"
local db = require"ZoneDB"
local zoneT=db.znameGetZoneT(request:header"host")
if zoneT and dname then
      local devT=db.nameGetDeviceT(zoneT.zid, dname)
      if devT then
         local s = request:session()
         local auth=s and s.authenticated
         local rsp={
            info=devT.info,
            regTime=ba.datetime(devT.regTime):ticks(),
            accessTime=ba.datetime(devT.accessTime):ticks(),
            dkey=auth and devT.dkey,
            canrem = auth,
         }
         devT.canrem = auth
         devT.dkey = auth and dkey
         response:json(rsp)
      end
end
response:senderror(404)

?>
