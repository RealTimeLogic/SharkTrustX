<?lsp
local fmt=string.format
local ispost = request:method() == "POST"
local data = ispost and app.xssfilter(app.trim(request:data())) or {state=request:data"state"}
local lgSend = require"log".sendmail

-----------------------------------------
local function accountForm(emsg)
----------------------------------------------
local autoReg = tonumber(zoneT.autoReg) > 0
?>
<h2>Create an Account</h2>
<div class="card card-body bg-light">
  <?lsp= emsg and fmt('<div class="alert alert-danger" role="alert">%s!</div>',emsg) or '' ?>
  <form id="pwdform" method="post">
    <div class="form-group">
      <label for="email">E-Mail:</label>
      <input type="text" name="email" id="email" class="form-control" placeholder="Enter your email address" autofocus required tabindex="1" required>
    </div>
    <div class="form-group">
      <label for="password">Password:</label>
      <input class="form-control" placeholder="Enter a great password" type="password" id="password" name="password" minlength="8" autofocus nowhitespace="true" tabindex="2" required />
    </div>
    <div class="form-group">
      <label for="password2">Confirm Password:</label>
      <input class="form-control" placeholder="Repeat your great password" type="password" id="password2" name="password2" equalTo="#password" nowhitespace="true" tabindex="3" required/>
    </div>
   <?lsp if not autoReg then ?>
    <div class="form-group">
      <label for="name">Name:</label>
      <input type="text" name="name" id="name" class="form-control" placeholder="Enter your full name" autofocus required tabindex="4" required>
    </div>
   <?lsp end ?>
    <input type="hidden" name="state" value="send" />
    <input type="hidden" name="isuser" value="true" />
    <input type="submit" class="btn btn-primary btn-block" value="Create" tabindex="5">
  </form>
</div>
<script>
$(function() {
    $("#pwdform").validate({
        rules: {
            email: {required: true, email: true},
            password: "required",
            password2: { equalTo: "#password" }
        }
    });
});
</script> 
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/jquery.validate.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/additional-methods.min.js"></script>
<?lsp end
----------------------------------------------
local function registrationCompletedForm(email, autoReg)
----------------------------------------------
local msg = autoReg and
      fmt('You may now <a href="login">login</a> using your email address %s as the username.',email) or
      fmt('User %s is now a registered user.<br>You may make this user a "power user" on the <a href="users">users</a> page.',email)
if not autoReg then
   local function sendEmail()
      lgSend{
         subject="Account accepted for "..zoneT.zname,
         to=email,
         body=fmt("Your account is now ready. You may login at the following URL: https://%s/login",zoneT.zname)
      }
   end
   ba.thread.run(sendEmail)
end
?>
<h2>Account Registered</h2>
<div class="card card-body bg-light">
<div class="alert alert-info" role="alert">
<p><?lsp=msg?></p>
</div>
</div>
<?lsp end
----------------------------------------------
local function registerForm()
----------------------------------------------
local emsg
if data.encrypted then
   local infoT = ba.json.decode(app.aesdecode(data.encrypted:match"^%s*%-*(.-)%-*%s*$" or "") or "")
   if infoT and infoT.zid == zoneT.zid and not db.getUserT(zoneT.zid, infoT.email) then
      local ha1Pwd = app.ha1(infoT.email, infoT.password)
      db.addUser(zoneT.zid, infoT.email, ha1Pwd, false)
      return registrationCompletedForm(infoT.email, infoT.autoReg)
   end
   emsg = "Please enter the correct data or <a href="..request:uri()..">restart account registration</a>"
end

local extrainfo = data.isuser and "An email with registration data has been sent to your email address. " or ""

?>
<h2>Register Account</h2>
<div class="card card-body bg-light">
  <?lsp= emsg and '<div class="alert alert-danger" role="alert">'..emsg..'!</div>' or '' ?>
  <form id="pwdform" method="post">
    <div class="form-group">
      <label for="SecCode"><?lsp=extrainfo?>Complete the account registration by copying the registration data from the email you received and paste this information into the field below:</label>
      <textarea style="font-family:monospace" rows="7" name="encrypted" class="form-control" placeholder="--------------------------------&#10;GSVPfHODQn_TJ5TV5fWKx2pG-UnJ3btH&#10;_HSMSGjozBy2bAmVEdNS-NEGTqQadnq         THIS IS AN EXAMPLE&#10;um_OY4FB_Tptp7q2J1bRx3kjnJuahz2&#10;ZiAK4MQjO3NIQ&#10;--------------------------------" autofocus required tabindex="1"></textarea>
      <input type="hidden" name="state" value="register" />
    </div>
    <input type="submit" class="btn btn-primary btn-block" value="Register" tabindex="2">
  </form>
</div>


<?lsp end
----------------------------------------------
local function pendingForm()
----------------------------------------------
?>
<h2>Account Pending</h2>
<div class="card card-body bg-light">
<div class="alert alert-info" role="alert">
<p>Your account information has been sent to the zone administrator and will be reviewed for acceptance. You will receive an email when accepted.</p>
</div>
</div>
<?lsp end
----------------------------------------------
local function sendForm()
----------------------------------------------

local email,password,name = data.email and data.email:lower(),data.password,data.name
local autoReg = tonumber(zoneT.autoReg) > 0
if not email or not password or (not autoReg and not name) then
   return accountForm('All fields are required')
end
if db.getUserT(zoneT.zid, email) or email == zoneT.admEmail:lower() then
   return accountForm('E-Mail address already registered')
end

local data=app.aesencode(ba.json.encode{
   email=email,
   password=password,
   autoReg=autoReg,
   zid=zoneT.zid
})
local i,line=1,"--------------------------------"
local t={line}
for j=32,#data,31 do table.insert(t,data:sub(i,j)) i=j+1 end
table.insert(t,data:sub(i))
table.insert(t,line)
data=table.concat(t,"\n")
local peer = request:peername()
if autoReg then
   local function sendEmail()
      lgSend{
         subject="Create account for "..zoneT.zname,
         to=email,
         body=fmt(
            "%s%s\n",
            "\nComplete your registration by copying the following data and pasting it into the online form:\n\n",
            data)
      }
   end
   ba.thread.run(sendEmail)
   registerForm()
else
   local function sendEmail()
      lgSend{
         subject=fmt("%s : %s requests access to %s",name,email,zoneT.zname),
         to=zoneT.admEmail,
         body=fmt(
            "%s\nhttps://%s/create?state=register\n\n%s\n",
            "\nAccept the registration request by copying the following data and pasting it into the online form:",
            zoneT.zname,data)
      }
   end
   ba.thread.run(sendEmail)
   pendingForm()
end

?>


<?lsp end

local actions = {
   register=registerForm,
   send=sendForm,
}

(actions[data.state] or accountForm)()

?>
