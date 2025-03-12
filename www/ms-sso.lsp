<?lsp

-- Manage the initial SSO redirect by sending the user to Azure AD for authentication.

local sso=app.sso(request:domain())
if sso then
   sso.sendredirect(request)
end
response:sendredirect"/"

?>
