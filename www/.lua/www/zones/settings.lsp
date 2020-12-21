<?lsp
local zname=request:header"host"
local data=request:data()
if request:method() == "POST" and data.terminate == "yes" then
  app.deleteZone(zname)
  response:sendredirect("https://"..app.settingsT.dn)
end
?>
<h1>Settings</h1>
<div class="card card-body bg-light h-100">
  <div class="alert alert-success  h-100" role="alert">
   <table>
   <tr><td>Owner:</td><td><?lsp=zoneT.admEmail?></td></tr>
   <tr><td>Registered:</td><td><?lsp=zoneT.regTime?></td></tr>
   <tr><td>Devices:</td><td><?lsp=db.countDevices4Zone(zoneT.zid)?></td></tr>
   <tr><td>Zone Key:</td><td><?lsp=zoneT.zkey?></td></tr>

   <tr><td>Secret:</td><td>
<?lsp
 local session = request:session() 
 if session.verification and session.verification == data.verification then
    print(zoneT.zsecret)
    session.verification=nil
 else
   print'<a href="verification">View secret</a>'
    end
?>
   </td></tr>

   </table>
</div>
