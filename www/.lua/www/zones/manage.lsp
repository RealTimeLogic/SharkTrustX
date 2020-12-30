<?lsp
local wanL = db.getWanL(zoneT.zid)
if #wanL > 0 then
   response:write'<h2>All Registered Devices</h2>'
else
   response:write'<h2>No Devices</h2><p>No registered devices!</p>'
   return
end
for _,wanAddr in ipairs(wanL) do
?>

<div class="card card-body bg-light">
<h4><?lsp=wanAddr?></h4>
<table class="table table-striped table-bordered">
  <thead class="thead-dark"><th>Name</th><th>IP Addr</th><th>Details</th></thead>
  <tbody class="devtab">
<?lsp
   for devT in db.getDevices4Wan(zoneT.zid,wanAddr) do
      response:write('<tr><td class="name">',devT.name,
                     '</td><td>',devT.localAddr,
                     '</td><td class="info"><div class="arrow darrow"></div></td></tr>')
   end
?>
  </tbody>
</table>
</div>
<?lsp end ?>

