<?lsp
local response=response
local relpath=relpath
local parentsT = parentRefT[relpath] or {}

local canAccess = userT and userT.canAccess or function(userType) return not userType end

local function emitMenu(menuL,nested)
   for _,m in ipairs(menuL) do
      if m.menu and canAccess(m.user) then
         local active = m.href == relpath
         if m.sub then
            local groupActive = parentsT[m.sub] and true or false
            response:write('<li class="nav-item nav-group',groupActive and ' is-active' or '', '">')
            if m.href then
               response:write('<a href="/',m.href,'" class="nav-group-title',active and ' is-active' or '', '"',active and ' aria-current="page"' or '', '>',m.name,'</a>')
            else
               response:write('<span class="nav-group-title">',m.name,'</span>')
            end
            response:write('<ul class="nav-sublist">')
            emitMenu(m.sub,true)
            response:write('</ul></li>')
         else
            response:write('<li class="nav-item"><a href="/',m.href,'" class="',nested and 'nav-sublink' or 'nav-link',active and ' is-active' or '', '"',active and ' aria-current="page"' or '', '>',m.name,'</a></li>')
         end
      end
   end
end

local function emitBreadcrumbs()
   local breadcrumbL = breadcrumbT[relpath]
   if breadcrumbL then
      for _,bc in ipairs(breadcrumbL) do
         if bc.href then
            response:write('<a href="',bc.href,'">',bc.name,'</a><span aria-hidden="true">/</span>')
         else
            response:write('<span>',bc.name,'</span><span aria-hidden="true">/</span>')
         end
      end
   end
   if activeMenuItem.name then
      response:write('<span aria-current="page">',activeMenuItem.name,'</span>')
   end
end
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?lsp=activeMenuItem.name and activeMenuItem.name.." | SharkTrustX" or "SharkTrustX"?></title>
  <link rel="icon" href="/favicon.ico">
  <link rel="stylesheet" href="/assets/style.css">
  <script src="/rtl/jquery.js"></script>
</head>
<body>
<div id="layout" class="app-shell">
  <button id="menuLink" class="menu-link" type="button" aria-label="Toggle navigation" aria-controls="menu" aria-expanded="false">
    <span></span>
  </button>

  <aside id="menu" class="side-nav" aria-label="Primary navigation">
    <div class="nav-inner">
      <a class="nav-brand" href="https://realtimelogic.com/products/SharkTrustX/">
        <span class="brand-mark" aria-hidden="true">X</span>
        <span class="brand-copy"><strong>SharkTrustX</strong><small>Trust services portal</small></span>
      </a>
      <nav>
        <ul class="nav-list">
          <?lsp emitMenu(menuL,false) ?>
        </ul>
      </nav>
      <div class="nav-account">
<?lsp if userT then ?>
        <span class="account-name"><?lsp=userT.name or userT.email?></span>
        <a href="/logout.lsp">Sign out</a>
<?lsp else ?>
        <span class="account-name">Guest access</span>
        <a href="/login.html">Sign in</a>
<?lsp end ?>
      </div>
    </div>
  </aside>

  <main id="main" class="main-pane">
    <header class="page-header">
      <div>
        <p class="eyebrow">SharkTrustX portal</p>
        <?lsp if activeMenuItem.name then response:write('<h1>',activeMenuItem.name,'</h1>') else response:write('<h1>SharkTrustX</h1>') end ?>
      </div>
      <div class="page-meta">
        <nav class="breadcrumbs" aria-label="Breadcrumb">
          <a href="/">Home</a>
          <?lsp if activeMenuItem.name and activeMenuItem.href ~= "index.html" then response:write('<span aria-hidden="true">/</span>'); emitBreadcrumbs() end ?>
        </nav>
<?lsp if userT then ?>
        <span class="page-user"><?lsp=userT.name or userT.email?></span>
<?lsp end ?>
      </div>
    </header>

    <?lsp lspPage(_ENV,relpath,io,page,app) ?>

    <footer class="site-footer">
      <span>&copy; Real Time Logic</span>
      <a href="https://realtimelogic.com/">realtimelogic.com</a>
    </footer>
  </main>
</div>

<div id="toastRegion" class="toast-region" aria-live="polite" aria-atomic="true"></div>
<script src="/assets/dashboard.js"></script>
<script src="/assets/service.js"></script>
</body>
</html>
