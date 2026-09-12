<?lsp

-- Manage the initial SSO redirect by sending the user to Azure AD for authentication.

local sso,err=app.sso(request:domain())
local status
if sso then
   local ok,unused
   ok,err,unused,status=sso.sendredirect(request)
   if ok then return end
end
local session=request:session(true)
session.msSsoResult={message=err or "Single Sign On is not available",status=status}
response:sendredirect"/ms-sso.html"

?>
