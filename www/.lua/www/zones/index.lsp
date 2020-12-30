<?lsp local function tabHeader() ?>
   <table class="table table-striped table-bordered">
     <thead class="thead-dark"><th>Name</th><th>IP Addr</th><?lsp=page.userT and '<th>Details</th>' or ''?></thead>
     <tbody class="devtab">
<?lsp end local function localDevProlog() ?>
   <h2>Local Devices</h2>
<?lsp tabHeader() end local function remDevProlog() ?>
   <h2>Remote Devices</h2>
<?lsp tabHeader() end local function tabEpilog() ?>
   </tbody></table>
<?lsp end

local devsTL={}
local hasProlog=false
local zname=page.zname
local arrow = page.userT and '<td class="info"><div class="arrow darrow"></div></td>' or ''
for devT in db.getDevices4Wan(zoneT.zid,app.peername(request) or "") do
   devsTL[devT.dkey] = devT
   if not hasProlog then
      hasProlog=true
      localDevProlog()
   end
   response:write('<tr><td><a class="name" target="_blank" href="https://',devT.name,'.',zoneT.zname,'">',devT.name,
                  '</a></td><td>',devT.localAddr,'</td>',arrow,'</tr>')
end
if hasProlog then
   tabEpilog()
else
   response:write'<h2>No Local Devices</h2><p>No devices are registered in your location.</p>'
end

hasProlog=false;
if page.userT then
   local rc=require"RevConnBridge"
   local userT=page.userT
   for devT in ((userT.type == "admin" or userT.poweruser) and db.getDevices4ZoneT(zoneT.zid) or db.getDevices4User(userT.uid)) do
      if not devsTL[devT.dkey] then
         local dz,active=rc.getDevInfo(devT.dkey)
         if dz then
            if not hasProlog then
               hasProlog=true
               remDevProlog()
            end
            if active then
               response:write('<tr><td><a class="name" target="_blank" href="https://',dz,'.',zoneT.zname,'">',devT.name,
                              '</a></td><td>',devT.wanAddr, " - ", devT.localAddr,'</td><td class="info"><div class="arrow darrow"></div></td></tr>')
            else
               response:write('<tr><td>',devT.name,
                              '</td><td>',devT.wanAddr, " - ", devT.localAddr,'</td><td class="info"><div class="arrow darrow"></div></td></tr>')
            end
         end
      end
   end
   if hasProlog then tabEpilog() end
end
?>   
