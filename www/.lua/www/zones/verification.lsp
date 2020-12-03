<?lsp
local data=request:data()
local session = request:session()
if request:method() == "POST" then
   if not session.referrer then response:sendredirect"/" end
   local ver = data.verification or ""
   response:sendredirect(session.referrer.."?verification="..ver)
end
session.referrer=data.ref or request:header"referer"
if not session.referrer then response:sendredirect"/" end
local fmt,sbyte=string.format,string.byte
session.verification = ba.rndbs(6):gsub(".",function(x) return fmt("%02X",sbyte(x)) end)
if not session.verification then response:sendredirect"/" end
local zname=request:header"host"
local zoneT=app.rwZoneT(app.rcZonesT()[zname])

local ebody=[[
You have requested a secure verification code to view secrets.

Please enter this secure verification code: %s

Reset your password and review your security settings if you did not request viewing secrets:
https://%s/login
]]

local peername=request:peername()
local function sendEmail()
   local send = require"log".sendmail
   send{
      subject="Secure two-step verification notification for "..zname,
      to=zoneT.uname,
      body=fmt(ebody, session.verification, zname)
   }
   log(false,"Requesting viewing secrets for %s originating from %s",zname,peername) 
end
ba.thread.run(sendEmail) 
?>

<h1>Enter your verification code</h1>

<div class="card card-body bg-light">
  <form id="verification" method="post">
    <div class="form-group">
      <p>A verification code has been sent to your email address. Please enter the code that you received.</p>
      <input type="text" name="verification" class="form-control" placeholder="Verification code" autofocus required tabindex="1"/>
    </div>
    <input type="submit" class="btn btn-primary btn-block" value="Enter" tabindex="2"/>
  </form>
</div> 
<script>
$("#verification").submit(function() {
setTimeout("window.location.href='/'", 3000)
});
</script>
