<?lsp
 local ispost = request:method() == "POST"
 if ispost then
    local data=request:data()
    local userT = app.login(zoneT, data.ba_username, data.ba_password)
    if userT then
      request:session(true).userT=userT
      if userT.type == "user" and not userT.poweruser then
        db.setUserAccess4Wan(zoneT.zid,userT.uid,app.peername(request))
      end
      response:sendredirect"/"
    end
    ba.sleep(1000)
 end
?>
<style>
#account a{float:right;color:gray;margin-left:1em}
</style>
<h2>Login</h2>
<div class="card card-body bg-light">
  <?lsp= ispost and '<div class="alert alert-danger" role="alert">Incorrect credentials!</div>' or '' ?>
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
  <span id="account"><a href="/recover">Forgot account?</a><a href="/create">Create an account</a></span>
</div>
