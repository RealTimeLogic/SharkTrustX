
-- Mini CMS for all registered zones

local parseLspPage,templatePage
local app,io=app,app.io -- must be a closure

local menuL=require"rwfile".json(io,".lua/www/zones.json")
assert(menuL, ".lua/www/zones.json parse error")

local parentRefT={}
local breadcrumbT={}
local pagesT={}
local menuT={}

local function buildRef(m,parentsT,breadcrumbL)
   if m.sub then
      parentsT[m.sub]=true
      table.insert(breadcrumbL,{name = m.name, href = m.href})
      for _,ms in ipairs(m.sub) do
         buildRef(ms,parentsT,breadcrumbL)
      end
   elseif m.href then
      menuT[m.href]=m
      parentRefT[m.href]=parentsT
      if #breadcrumbL > 0 then breadcrumbT[m.href]=breadcrumbL end
   end
end

for _,m in ipairs(menuL) do
   buildRef(m,{},{})
end

local function cmsfunc(_ENV,relpath,zname)
   local m,pageT,userT
   if zoneT then
      if #relpath == 0 or relpath:find"/$" then
         relpath = relpath.."index.html"
      end
      m = menuT[relpath]
      if not m then
         if not relpath:find"%.html$" then return false end
         response:setstatus(404)
         relpath = "404.html"
         m={}
      end
      pageT=pagesT[relpath]
      if not pageT then
         pageT={}
         pagesT[relpath]=pageT
      end
      local s = request:session()
      userT = s and s.userT -- see login.lsp
      if userT then -- Authenticated
         if not userT.canAccess(m.user) then -- canAccess() set in .preload - app.login()
            response:sendredirect"/" -- No access (ACL exception)
         end
      else -- Not authenticated
         if m.user then -- Page requires auth.
            response:sendredirect"/login.html"
         end
      end
      response:setheader("strict-transport-security","max-age=15552000; includeSubDomains")
   else
      relpath = "no-zone.html"
      m={}
   end

   _ENV.parentRefT=parentRefT
   _ENV.breadcrumbT=breadcrumbT
   _ENV.menuL=menuL
   _ENV.relpath=relpath
   _ENV.activeMenuItem=m
   _ENV.userT=userT
   _ENV.lspPage=parseLspPage(".lua/www/zones/"..relpath)

   --Enable when working on template.lsp
   --local _,templatePage=io:dofile(".lua/www/engine.lua",app)

   templatePage(_ENV,path,io,pageT,app)

   return true
end

local function init(lsp,template)
   parseLspPage,templatePage = lsp,template 
   return cmsfunc
end

return init
