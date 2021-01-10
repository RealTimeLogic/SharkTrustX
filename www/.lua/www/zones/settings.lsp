<?lsp

if request:header"x-requested-with" then
   local enabled = request:data"autoReg" == "true"
   db.setAutoReg(zoneT.zid,enabled)
   response:json{autoReg=enabled}
end

?>
<h2>Settings</h2>
<div class="card card-body bg-light h-100">

   <table>
   <tr><td>Owner:</td><td><?lsp=zoneT.admEmail?></td></tr>
   <tr><td>Registered:</td><td><?lsp=zoneT.regTime?></td></tr>
   <tr><td><span title="Enable automatic account registration without requiring administrator acceptance">Auto Registration:</span></td><td><input type="checkbox" id="autoReg" name="autoReg" <?lsp=db.getAutoReg(zoneT.zid) and "checked" or ""?>></td></tr>
   <tr><td>Devices:</td><td><?lsp=db.countDevices4Zone(zoneT.zid)?></td></tr>
   <tr><td>Zone Key:</td><td><?lsp=zoneT.zkey?></td></tr>

   <tr><td>Secret:</td><td>
<?lsp
 local session = request:session() 
 if session.verification and session.verification == request:data"verification" then
    print(zoneT.zsecret)
    session.verification=nil
 else
   print'<a href="verification">View secret</a>'
 end
?>
   </td></tr>
   </table>
</div>
<script>
    $("#autoReg").click(function() {
        $.getJSON(window.location,{autoReg:$(this).prop("checked")});
    });
</script>
