<?lsp
   local ok,err,ispost=true
   if request:method()=="POST" then
      ispost=true
      local data=request:data()
      local lgSend = require"log".sendmail
      ok,err = lgSend{
         subject=data.subject,
         to=data.email,
         body=data.message
      }
   end
?>
<h2>Send E-Mail</h2>
<p>Send email (and test the email configuration settings).</p>
<div class="card card-body bg-light">
<?lsp if ispost and ok then ?>
<div class="alert alert-success" role="alert">E-mail sent!</div>
<?lsp elseif ispost and err then ?>
<div class="alert alert-danger" role="alert">Sending e-mail failed: <?lsp=err?>!</div>
<?lsp end ?>
<form id="valform" method="post">
<div class="form-group">
<label for="email">Email Address:</label>
<input class="form-control" placeholder="Enter recipient's email address" type="text" name="email" minlength="9" nowhitespace="true" autofocus required tabindex="1">
</div>
<div class="form-group">
<label for="subject">Subject:</label>
<input class="form-control" placeholder="Enter e-mail subject" type="text" name="subject" minlength="9" required tabindex="2">
</div>
<div class="form-group">
<label for="message">Message:</label>
<textarea rows="10" style="width:100%" name="message"  tabindex="3"></textarea>
</div>
<input type="submit" class="btn btn-primary btn-block" value="Send" tabindex="4">
</form>
<script>
$(function() {
    $("#valform").validate({
        rules: {
            subject: "required",
            email: { required: true, email: true },
        }
    });
});
</script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/jquery.validate.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/jquery-validation@1.17.0/dist/additional-methods.min.js"></script>
 
