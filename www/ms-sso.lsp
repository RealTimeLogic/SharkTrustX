<?lsp

-- Manage the initial SSO redirect by sending the user to Azure AD for authentication.

local db=require"ZoneDB"
local host=request:domain()
local zoneT=db.znameGetZoneT(host)
if zoneT and db.getSsoEnabled(zoneT.zid) then
   local ssoCfgT=db.getSsoCfg(zoneT.zid)
   ssoCfgT.redirect_uri=string.format("https://%s/ms-sso.html",host)
   require"ms-sso".sendredirect(request,ssoCfgT)
end
response:sendredirect"/"

?>
