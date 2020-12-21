<?lsp

local devsTL={}
for devT in db.getDevices4Wan(zoneT.zid,app.peername(request) or "") do
   table.insert(devsTL,devT)
end
if #devsTL == 0 then
   response:write'<h1>No Devices</h1><p>No devices are registered in your location.</p>'
   return
end
?>
<h1>Local Devices</h1>

<table class="table table-striped table-bordered">
  <thead class="thead-dark"><th>Name</th><th>IP Addr</th><th>Details</th></thead>
  <tbody class="devtab">
<?lsp
   local zname=page.zname
   for _,devT in ipairs(devsTL) do
      response:write('<tr><td><a class="name" href="https://',devT.name,'.',zoneT.zname,'">',devT.name,
                     '</a></td><td>',devT.localAddr,'</td><td class="info"><div class="arrow darrow"></div></td></tr>')
   end
?>
  </tbody>
</table>


