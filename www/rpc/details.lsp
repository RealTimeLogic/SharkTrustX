<?lsp

local dname=request:data"name"
local db = require"ZoneDB"
local zoneT=db.znameGetZoneT(request:header"host")
if request:user() and zoneT and dname then
   local devT=db.nameGetDeviceT(zoneT.zid, dname)
   if devT then
      local s = request:session()
      if s then
         local user = s.userT and s.userT.type
         local adm = user=="admin"
         local power=adm or user=="power"
         local dz,active,lastActiveTime,activeCons = require"RevConnBridge".getDevInfo(devT.dkey)

         local rsp={
            info=devT.info,
            regTime=ba.datetime(devT.regTime or "MIN"):ticks(),
            accessTime=ba.datetime(devT.accessTime or "MIN"):ticks(),
            dkey = adm and devT.dkey,
            rname = 0~=#devT.rname and devT.rname,
            setrname=power,
            canrem = power,
         }
         if dz then
            rsp.dz=dz
            rsp.fqn=dz.."."..zoneT.zname
            rsp.active=active
            rsp.lastActiveTime=lastActiveTime:ticks()
            rsp.activeCons=activeCons
         end
      response:json(rsp)
      end
   end
end
response:senderror(404)

?>
