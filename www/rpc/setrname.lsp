<?lsp
local function trim(s) return s and s:gsub("^%s*(.-)%s*$", "%1") end
local d=request:data()
local dname,rname=trim(d.dname),trim(d.rname)
local db = require"ZoneDB"
local sensitive=require"SensitiveAction"
local zoneT=db.znameGetZoneT(request:header"host")
local s = request:session()
local userT = s and s.userT -- Set if authenticated
local function send(status,body)
   response:setstatus(status)
   response:setheader("Cache-Control","no-store")
   response:json(body)
end
if request:method() ~= "POST" then
   response:setheader("Allow","POST")
   return send(405,{ok=false,err="This change requires POST."})
end
if not userT or not zoneT or not userT.canAccess"power" then
   return send(403,{ok=false,err="No access"})
end
if not request:header"x-requested-with" or not sensitive.validCsrf(s,d.csrf) then
   return send(403,{ok=false,err="This page has expired. Reload Manage Devices and try again."})
end
local devT=dname and rname and db.nameGetDeviceT(zoneT.zid,dname)
if not devT then return send(404,{ok=false,err="Not found"}) end
if #rname > 0 and (#rname < #dname+3 or rname:sub(-#dname) ~= dname) then
   return send(400,{ok=false,err="The name must prefix "..dname})
end

local defresp=response:deferred()
db.setDevRname(devT.did,rname,function(ok)
   if ok then require"RevConnBridge".removeDevice(devT.dkey) end
   if not defresp:valid() then return end
   local body=ba.json.encode(ok and {ok=true} or {ok=false,err="The database write did not complete. Please try again."})
   defresp:setstatus(ok and 200 or 503)
   defresp:setheader("Cache-Control","no-store")
   defresp:setheader("Content-Type","application/json; charset=utf-8")
   defresp:setcontentlength(#body)
   defresp:send(body)
   defresp:close()
end)

?>
