<?lsp
local data = request:data()
if request:header"x-requested-with" then
   local uid=data.uid
   if uid then
      if data.poweruser then
         db.setPoweruser(uid,data.poweruser=="true")
      elseif data.did and data.access then
         db.setDevAccess4User(uid, data.did, data.access=="true")
      end
   end
   response:json(data)
end

----------------------------------------------
local function listAllUsers()
----------------------------------------------
?>
<h2>Users</h2>
<div class="card card-body bg-light h-100">
  <table class="table table-striped table-bordered">
    <thead class="thead-dark"><th>E-Mail</th><th>Power User</th></thead>
    <tbody class="devtab">
<?lsp
   local fmt=string.format
   for uid,email,poweruser in db.getUsers() do
      response:write('<tr><td>',poweruser and email or
                     fmt('%s%s%s%s','<a href="?u=',email,'">',email,'</a>'),
                     '</td><td>',
                     poweruser,
                     '<input uid="',uid,'" type="checkbox"', poweruser and ' checked' or '', ' email="',email,'">',
                     '</td></tr>')
   end
?>
     </tbody>
  </table>
<p style="position:absolute;right:5px;bottom:5px"><a class="btn btn-primary" href="?remove=">Select users to remove</a></p>
</div>
<script>
    $("input").change(function() {
        const self=$(this);
        const email=self.attr("email");
        const poweruser=self.prop("checked");
        const html = poweruser ? email : '<a href="?u='+email+'">'+email+'</a>';
        self.parent().parent().children(":first").html(html);
        $.getJSON(window.location,{uid:self.attr("uid"),poweruser:poweruser});
    });
</script>
<?lsp end
----------------------------------------------
local function manageUser(email)
----------------------------------------------
   local userT = db.getUserT(zoneT.zid,email)
   if not userT then response:sendredirect"" end
   local devsAccessT=db.getDevices4User(userT.uid)
   response:write('<h4>Remote Connection Access for: ',email,'</h4>')
   local wanL = db.getWanL(zoneT.zid)
   for _,wanAddr in ipairs(wanL) do
?>
<div class="card card-body bg-light">
<h4><?lsp=wanAddr?></h4>
<table class="table table-striped table-bordered">
  <thead class="thead-dark"><th>Name</th><th>IP Addr</th><th>Access</th><th>Details</th></thead>
  <tbody class="devtab">
<?lsp
   for devT in db.getDevices4Wan(zoneT.zid,wanAddr) do
      response:write('<tr><td class="name">',devT.name,
                     '</td><td>',devT.localAddr,
                     '</td>',
                     '<td>',
                     '<input name="',devT.did,'" type="checkbox"', devsAccessT[devT.did] and ' checked' or '','>',
                     '</td><td class="info"><div class="arrow darrow"></div></td></tr>')
   end
?>
  </tbody>
</table>
</div>
<?lsp end?>
<script>
    $("input").change(function(e) {
        const self=$(this);
        console.log(self.attr("name"));
        $.getJSON(window.location,{uid:<?lsp=userT.uid?>,did:self.attr("name"),access:self.prop("checked")},function(){});
    });
</script>
<?lsp end
----------------------------------------------
local function removeUsers()
----------------------------------------------
if request:method()=="POST" then
   local usersL={}
   for name,value in request:datapairs() do
      if name == "uid" then
        table.insert(usersL,value) -- insert uid
      end
   end
   db.removeUsers(usersL)
   response:sendredirect""
end

?>
<h2>Remove Users</h2>
<div class="card card-body bg-light h-100">
 <form method="post">
  <table class="table table-striped table-bordered">
    <thead class="thead-dark"><th>E-Mail</th><th>Select</th></thead>
    <tbody class="devtab">
<?lsp
   local fmt=string.format
   for uid,email,poweruser in db.getUsers() do
      response:write('<tr><td>',poweruser and email or
                     fmt('%s%s%s%s','<a href="?u=',email,'">',email,'</a>'),
                     '</td><td>',
                     poweruser,
                     '<input name="uid" value="',uid,'" type="checkbox">',
                     '</td></tr>')
   end
?>
     </tbody>
  </table><br/>
  <input type="submit" class="btn btn-primary btn-block" value="Remove Selected Users">
 </form>
</div>
<?lsp end



if data.u then
   manageUser(data.u)
elseif data.remove then
   removeUsers()
else
   listAllUsers()
end

?>
