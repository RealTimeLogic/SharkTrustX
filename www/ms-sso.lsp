<?lsp

-- Manage the initial SSO redirect by sending the user to Azure AD for authentication.

local sso,err=app.sso(request:domain())
if sso then
   local ok
   ok,err=sso.sendredirect(request)
   if ok then return end
end
local session=request:session(true)
session.msSsoResult={message=err or "Single Sign On is not available"}
response:sendredirect"/ms-sso.html"

?>
