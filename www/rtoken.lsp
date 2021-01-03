<?lsp
if "HEAD" == request:method() then
   require"RefreshTokenManager".cmdGetToken(request)
else
   response:senderror(404)
end
?>
