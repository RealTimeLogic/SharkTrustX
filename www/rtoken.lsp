<?lsp
if "HEAD" == request:method() then
   require"RefreshTokenManager".cmdGetToken(request)
else
   response:setstatus(404)
end
?>
