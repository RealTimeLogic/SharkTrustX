<?lsp
local zname=request:header"host"
local data=request:data()
if request:method() == "POST" and data.terminate == "yes" then
  app.deleteZone(zname)
  response:sendredirect("https://"..app.settingsT.dn)
end
local zkey = app.rcZonesT()[zname]
local zoneT=app.rwZoneT(zkey)
local dCount=0
for _ in pairs(zoneT.devices) do dCount = dCount + 1 end
local session = request:session()
?>
<h1>Settings</h1>
<div class="card card-body bg-light h-100">
  <div class="alert alert-success  h-100" role="alert">
   <table>
   <tr><td>Owner:</td><td><?lsp=zoneT.uname?></td></tr>
   <tr><td>Registered:</td><td><?lsp=os.date("%c",zoneT.rtime)?></td></tr>
   <tr><td>Devices:</td><td><?lsp=dCount?></td></tr>
   <tr><td>Zone Key:</td><td><?lsp=zkey?></td></tr>

   <tr><td>Secret:</td><td>
<?lsp
 if session.verification and session.verification == data.verification then
    print(zoneT.secret)
    session.verification=nil
 else
   print'<a href="verification">View secret</a>'
    end
?>
   </td></tr>

   </table>
</div>
