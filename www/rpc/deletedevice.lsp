<?lsp
local function send(status,body)
   response:setstatus(status)
   response:setheader("Cache-Control","no-store")
   response:json(body)
end
if request:method() ~= "POST" then
   response:setheader("Allow","POST")
   return send(405,{ok=false,err="Device removal requires POST."})
end
local data=request:data()
local db=require"ZoneDB"
local sensitive=require"SensitiveAction"
local zoneT=db.znameGetZoneT(request:header"host")
local session=request:session()
local userT=session and session.userT
if not userT or not zoneT or not userT.canAccess"power" then
   return send(403,{ok=false,err="No access"})
end
if not request:header"x-requested-with" or not sensitive.validCsrf(session,data.csrf) then
   return send(403,{ok=false,err="This page has expired. Reload Manage Devices and try again."})
end
local dname=type(data.name) == "string" and data.name or nil
local devT=dname and db.nameGetDeviceT(zoneT.zid,dname)
if not devT then return send(404,{ok=false,err="Not found"}) end

local defresp=response:deferred()
app.deleteDevice(zoneT,devT.dkey,function(ok,err,bindOk)
   if not defresp:valid() then return end
   defresp:setheader("Cache-Control","no-store")
   defresp:setheader("Content-Type","application/json; charset=utf-8")
   local result=ok and {ok=true} or {ok=false,err="The database write did not complete. Please try again."}
   if ok and not bindOk then result.warning="The device was removed, but DNS could not be refreshed immediately." end
   local body=ba.json.encode(result)
   defresp:setstatus(ok and 200 or 503)
   defresp:setcontentlength(#body)
   defresp:send(body)
   defresp:close()
end)
?>
