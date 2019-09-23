<?lsp

local host = request:header"host"
if not request:issecure() then
   if not host then response:senderror(404) return end
   response:sendredirect("https://"..host)
end

local zonesT,time = app.zonesDB()

local dnT
if not zonesT then -- If new installation
   dnT={}
elseif page.time ~= time then
   page.time = time
   page.zonesT = zonesT
   dnT = {}
   for zkey,zoneT in pairs(zonesT) do dnT[zoneT.zname]=zkey end
   page.dnT=dnT
else
   dnT=page.dnT
end

local isadmin
local zkey=dnT[host]
if zkey then
   local s = request:session()
   isadmin = s and s.zoneadmin
else
   if host ~= app.settingsT.dn then
      response:sendredirect("https://"..app.settingsT.dn)
   end
   if not page.aeskey then
      page.aeskey=ba.aeskey(32)
   end
end

local data = app.xssfilter(app.trim(request:data()))



local function emitValidateForm()
   response:write[[
<h1>Register</h1>
<p>Register for Real Time Logic's Let's Encrypt DNS Service.</p>
<div class="well">
<form id="valform" method="post">
<div class="form-group">
<label for="email">Domain Name:</label>
<input class="form-control" placeholder="Enter your domain name" type="text" name="domain" minlength="7" autofocus nowhitespace="true" tabindex="1">
</div>
<div class="form-group">
<label for="email">Email Address:</label>
<input class="form-control" placeholder="Enter company email address" type="text" name="email" minlength="9" nowhitespace="true" tabindex="2">
</div>
<iframe style="width:100%;height:300px" src="license.html"></iframe>
<input id="changesub" class="btn btn-primary" type="submit" value="Accept and Sign Up" tabindex="3" />
 </form>
</div>
<script>
$(function() {
    $("#valform").validate({
        rules: {
            domain: "required",
            email: { required: true, email: true },
        }
    });
});
</script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/jquery.validate.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/additional-methods.min.js"></script>
]]
end





local function sendValidationEmail(email, domain)
   local valkey=ba.aesencode(page.aeskey,ba.json.encode{e=email,d=domain})
   local send = require"log".sendmail
   send{
      subject="DNS Service E-Mail Validation",
      to=email,
      body=string.format([[

Validation key:
%s

Complete the validation by navigating to the following URL and by entering the validation key:
https://%s/validate/
]], valkey, app.settingsT.dn)
   }
   response:write("<p>We have dispatched an email with setup instructions to ",email,".</p>",
                  "<p>Please check your spam box and/or spam filters if you do not receive this email soon.</p>")
end




local function enterValidationKey()
response:write[[
<h1>Enter Validation Key</h1>
<div class="well">
<form id="valform" method="post" action="/">
<div class="form-group">
<label for="email">Validation Key:</label>
<input class="form-control" placeholder="Validation Key" type="text" name="v" autofocus nowhitespace="true" tabindex="1">
</div>
<input id="changesub" class="btn btn-primary" type="submit" value="Submit" tabindex="2" />
 </form>
</div>
]]
end


local function emitInvalidKey()
   response:write'<h1>Invalid Validation Key!</h1><p>Invalid key or key has expired.</p><p><a href="/">Request new validation</a></p>'
end

local function emailAddrOk(email)
   if io:dofile".lua/freeproviders.lua"[email:match"@(.+)"] then
      response:write"<h1>E-Mail address not accepted</h1><p>Please use your company email address.</p><p><b>Alternatively:</b><br><a href='https://github.com/RealTimeLogic/BACME'>Copy this service's code source from Github</a> and set up your own service.</p><p><a href='/'>Continue</a></p>"
      return false
   end
   return true
end

local function notAlreadyReg(domain)
   if dnT[domain] then
      response:write('<h1>Domain in use</h1><p>Domain already registered!</p><p><a href="/">Register new domain</a></p>')
      return false
   end
   return true
end


local function validateAccount(vkey, email, domain)
   local rsp=ba.exec("whois "..domain) or "FAILED!"
   local rspl=rsp:lower()
   local ns=app.settingsT
   if rspl:find(ns.ns1,1,true) and rspl:find(ns.ns2,1,true) then
      response:write('<form id="pwdform" method="post"><div class="form-group"><label>Username:</label><p>',email,"</div>")
      response:write[[
<div class="form-group">
<label for="password">Admin Password:</label>
<input class="form-control" placeholder="Enter a password" type="password" id="password" name="password" minlength="8" autofocus nowhitespace="true" tabindex="1"
</div>
<div class="form-group">
<label for="password2">Confirm Password:</label>
<input class="form-control" placeholder="Repeat password" type="password" id="password2" name="password2" equalTo="#password" nowhitespace="true" tabindex="2">
</div>
]]
      response:write('<input type="hidden" name="v" value="',vkey,'">')
      response:write[[
<input id="changesub" class="btn btn-primary" type="submit" value="Submit" tabindex="3">
 </form>
<script>
$(function() {
    $("#pwdform").validate({
        rules: {
            password: "required",
            password2: { equalTo: "#password" }
        }
    });
});
</script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/jquery.validate.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/additional-methods.min.js"></script>
]]
   else
      response:write(
        '<h1>Invalid Domain Name Servers</h1><p>The domain name servers for your domain must be set to:</p><ul><li>',
        ns.ns1,
        '</li><li>',
        ns.ns2,
        '</li></ul><p>Note that it may take up to 48 hours for DNS changes to propagate. Please keep the validation key and retry later.</p>')
      response:write("<p>Whois response:</p><pre>",rsp,"</pre>")
   end
end


local function sendRegCompletedEmail(email,zkey,domain)
   local send = require"log".sendmail
   send{
      subject="DNS Service Account Information",
      to=email,
      body=string.format("Your zone key:\n%s\n\nYour zone URL:\nhttps://%s",
                         zkey,domain)
   }
end

local function registerAccount(email, domain, password)
   local zkey=app.createzone(domain, email, password)
   response:write"<h1>Registration Complete</h1><p>You will receive an email when your account is ready.</p>"
   local function send()
      ba.thread.run(function() sendRegCompletedEmail(email,zkey,domain) end)
   end
   ba.timer(send):set(120000,true)
end

local function emitLoginForm(failed)
   response:write'<h1>Zone Admin Login</h1><div class="well">'
   if failed then response:write'<div class="alert alert-danger" role="alert">Incorrect credentials!</div>' end
   response:write[[
<form method="post" id="login_form">
<div class="form-group">
<label for="Username">Username:</label>
<input type="text" name="ba_username" class="form-control" id="Username" placeholder="Enter your E-Mail address" autofocus required tabindex="1">
</div>
<div class="form-group">
<label for="Password">Password:</label>
<input type="password" name="ba_password" class="form-control" id="Password" placeholder="Enter your password" required tabindex="2">
</div>
<input type="submit" class="btn btn-primary btn-block" value="Enter" tabindex="3">
</form>
</div>
]]
end


local function emitSettings()
   response:write('<h1>Settings</h1><div class="well"><div class="alert alert-success" role="alert">Zone Key: ',
                  zkey,
                  '</div>')
   response:write[[
<div class="form-group">&nbsp;</div>
<form method="post">
<div class="form-group">
<input type="submit" class="btn btn-primary btn-block" id="termbut" value="Terminate Account">
<input type="hidden" id="terminate" name="terminate" value="no">
</div>
</div>
<script>
$(function() {
    $("#termbut").click(function(){
        var yes = prompt("Enter 'yes' to terminate your account","no");
        $("#terminate").val(yes);
        return yes == "yes";
    });
});
</script>
]]
end


local function hasElements(t, loconly)
   if t and next(t) then return true end
   if loconly then
      response:write'<h2>No Devices!</h2><p>No devices are registered in your location.</p>'
   else
      response:write'<h2>No Devices!</h2><p>Database empty.</p>'
   end
end

local function emitTabHeader()
   response:write(
      '<table class="table table-striped table-bordered">',
      '<thead><tr><th>Name</th><th>IP Addr</th><th>Access</th><th>Details</th></tr></thead><tbody>')
end
local function emitTabFooter()
   response:write'</tbody></table>'
end

local time = os.time()
local function fmtTime(time)
   if time - time > 31536000 then
      return os.date('%y %b %d',time or 0)
   end
   return os.date('%b %d',time or 0)
end


local function emitLocalDevices()
   local zDB=app.zoneDevDB(zkey)
   local zwDB=app.zoneWanDB(zkey)
   local devsT=zwDB[app.peername(request)]
   if hasElements(devsT, true) then
      response:write'<h2>Local Devices</h2>'
      emitTabHeader()
      for k,v in pairs(devsT) do
         local dT=zDB[k]
         local la = fmtTime(dT.time)
         response:write('<tr><td><a href="https://',dT.name,'.',host,'">',dT.name,
                        '</a></td><td>',dT.ip,'</td><td>',la,'</td><td class="small">',
                        dT.info,'</td></tr>')
      end
      emitTabFooter()
   end
end

local function emitDevices()
   if not isadmin then return emitLocalDevices()  end
   local admip = app.peername(request)
   local zDB=app.zoneDevDB(zkey)
   if hasElements(zDB) then
      for ip, wT in pairs(app.zoneWanDB(zkey)) do
         response:write('<h4>',ip,'</h4>')
         emitTabHeader()
         if admip == ip then
            for dkey in pairs(wT) do
               local dT=zDB[dkey]
               local la = fmtTime(dT.time)
               response:write('<tr><td><a href="https://',dT.name,'.',host,'">',dT.name,
                              '</a></td><td>',dT.ip,'</td><td>',la,'</td><td class="small">',
                              dT.info,'</td></tr>')
            end
         else
            for dkey in pairs(wT) do
               local dT=zDB[dkey]
               local la = fmtTime(dT.time)
               response:write('<tr><td>',dT.name,'</td><td>',dT.ip,'</td><td>',
                              la,'</td><td class="small">',dT.info,'</td></tr>')
            end
         end
         emitTabFooter()
      end
   end
end



?>
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>DNS Service</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="/assets/css/bootstrap.min.css">
    <link rel="stylesheet" href="/assets/css/styles.css">
    <script src="/assets/js/jquery-1.11.2.min.js"></script>
    <script src="/assets/js/bootstrap.min.js"></script>
  </head>
  <body>
      <nav class="navbar navbar-fixed-top navbar-inverse" role="navigation">
      <div class="container-fluid">
        <div class="navbar-header">
          <button type="button" class="navbar-toggle collapsed" data-toggle="collapse" data-target="#bs-example-navbar-collapse-1">
            <span class="sr-only">Toggle navigation</span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
          </button>
          <a href="/" class="navbar-brand">DNS Service</a>
        </div>
        <div class="collapse navbar-collapse" id="bs-example-navbar-collapse-1">
          <ul class="nav navbar-nav">
<?lsp
if zkey then
   response:write('<li><a href="?a=',isadmin and 's' or 'l','">',isadmin and 'Settings' or 'Login','</a></li>')
end
?>
          </ul>
        </div>
      </div>
    </nav>
    <div class="container-fluid">
      <div class="row">
         <div class="col-sm-12">
<?lsp

 local ispost = request:method() == "POST"
 if zkey then
    if data.a=="l" then
       if ispost and app.checkCredentials(zonesT[zkey], data.ba_username, data.ba_password) then
          request:session(true).zoneadmin=true
          response:sendredirect"/"
       end 
       emitLoginForm(ispost)
    elseif data.a=="s" then
       if ispost and data.terminate == 'yes' then
          app.deleteZone(host)
          response:sendredirect("https://"..app.settingsT.dn)
       end
       emitSettings()
    else
       emitDevices()
    end
 elseif data.v then
    if #data.v == 0 then
       enterValidationKey()
    else
       local info=ba.json.decode(ba.aesdecode(page.aeskey,data.v) or "")
       if info then
          if notAlreadyReg(info.d) then
             if data.password and data.password == data.password2 then
                registerAccount(info.e,info.d,data.password) 
             else
                validateAccount(data.v,info.e,info.d)
             end
          end
       else
          emitInvalidKey()
       end
    end
 else
    if data.email and data.domain then
       if emailAddrOk(data.email) and notAlreadyReg(data.domain) then
          sendValidationEmail(data.email, data.domain)
       end
    else
       emitValidateForm()
    end
 end
 collectgarbage()


?>
        </div>
      </div>
    </div>
  </body>
</html>
