<?lsp
local response=response
local parentRefT=parentRefT
local relpath=relpath
local emptyT={}
local parentsT = parentRefT[relpath]

local canAccess = userT and userT.canAccess or function(userType) return not userType end

local function emitMenu(menuL)
   for _,m in ipairs(menuL) do
      if m.class and canAccess(m.user) then
         response:write('<li class="nav-item', parentsT[m.sub] and  ' menu-open' or '','"><a href="/',m.href,
                        '" class="nav-link',m.href == relpath and ' active' or '','"><i class="',m.class,'"></i><p>',m.name)
         if m.sub then
            response:write('<i class="right fas fa-angle-left"></i></p></a><ul class="nav nav-treeview">')
            emitMenu(m.sub)
            response:write('</ul></li>')
         else
            response:write('</p></a></li>')
         end
      end
   end
end


?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SharkTrustX</title>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Source+Sans+Pro:300,400,400i,700&display=fallback">
  <link rel="stylesheet" href="/plugins/fontawesome-free/css/all.min.css">
  <link rel="stylesheet" href="https://code.ionicframework.com/ionicons/2.0.1/css/ionicons.min.css">
  <link rel="stylesheet" href="/plugins/icheck-bootstrap/icheck-bootstrap.min.css">
  <link rel="stylesheet" href="/dist/css/adminlte.min.css">
  <link rel="stylesheet" href="../../plugins/toastr/toastr.min.css">
  <link rel="stylesheet" href="/assets/style.css">
  <script src="/rtl/jquery.js"></script>
</head>
<body class="hold-transition sidebar-mini layout-fixed">
<div class="wrapper">
  <!-- Navbar -->
  <nav class="main-header navbar navbar-expand navbar-white navbar-light">
    <!-- Left navbar links -->
    <ul class="navbar-nav">
      <li class="nav-item">
        <a class="nav-link" data-widget="pushmenu" href="#" role="button"><i class="fas fa-bars"></i></a>
      </li>
    </ul>

   <ul class="navbar-nav ml-auto">
<?lsp if userT then ?>
      <li class="nav-item d-sm-inline-block">
        <span class="nav-link"><?lsp=userT.name or userT.email?></span>
      </li>
      <li class="nav-item d-sm-inline-block">
        <a href="/logout.lsp" class="nav-link">Logout</a>
      </li>
<?lsp else ?>
      <li class="nav-item d-sm-inline-block">
        <a href="/login.html" class="nav-link">Login</a>
      </li>
<?lsp end ?>
    </ul>

  </nav>
  <!-- /.navbar -->

  <!-- Main Sidebar Container -->
  <aside class="main-sidebar sidebar-dark-primary elevation-4">
    <!-- Brand Logo -->
    <a href="https://realtimelogic.com/products/SharkTrustX/" class="brand-link">
      <img src="/dist/img/SharkTrustLogo.png" alt="SharkTrustX Logo" class="brand-image img-circle elevation-3" style="opacity: .8">
      <span class="brand-text font-weight-light">SharkTrustX</span>
    </a>

    <!-- Sidebar -->
    <div class="sidebar">
      <!-- Sidebar Menu -->
      <nav class="mt-2">
        <ul class="nav nav-pills nav-sidebar flex-column" data-widget="treeview" role="menu" data-accordion="false">
          <!-- Add icons to the links using the .nav-icon class
               with font-awesome or any other icon font library -->

<?lsp emitMenu(menuL) ?>

        </ul>
      </nav>
      <!-- /.sidebar-menu -->
    </div>
    <!-- /.sidebar -->
  </aside>

  <!-- Content Wrapper. Contains page content -->
  <div class="content-wrapper">
    <!-- Content Header (Page header) -->
    <div class="content-header">
      <div class="container-fluid">
        <div class="row mb-2">
          <div class="col-sm-6">
            <?lsp if activeMenuItem.name then response:write('<h1 class="m-0">',activeMenuItem.name,'</h1>') end ?>
          </div><!-- /.col -->
          <div class="col-sm-6">
           <ol class="breadcrumb float-sm-right">
           <li class="breadcrumb-item"><a href="/">Home</a></li>
<?lsp
local breadcrumbL = breadcrumbT[relpath]
if breadcrumbL then
   for _,bc in ipairs(breadcrumbL) do
      if bc.href then
         response:write('<li class="breadcrumb-item"><a href="',bc.href,'">',bc.name,'</a></li>')
      else
         response:write('<li class="breadcrumb-item">',bc.name,'</li>')
      end
   end
end
response:write('<li class="breadcrumb-item active">',activeMenuItem.name,'</li>')
?>
            </ol>
          </div><!-- /.col -->
        </div><!-- /.row -->
      </div><!-- /.container-fluid -->
    </div>
    <!-- /.content-header -->

    <?lsp lspPage(_ENV,relpath,io,page,app) ?>

    <!-- Main content -->
    <!-- /.content -->
  </div>
  <!-- /.content-wrapper -->
  <footer class="main-footer">
    <strong>Copyright &copy; <a href="https://realtimelogic.com/">Real Time Logic</a>.</strong>
    All rights reserved.
    <div class="float-right d-none d-sm-inline-block">

    </div>
  </footer>

  <!-- Control Sidebar -->
  <aside class="control-sidebar control-sidebar-dark">
    <!-- Control sidebar content goes here -->
  </aside>
  <!-- /.control-sidebar -->
</div>
<!-- ./wrapper -->

<script src="/plugins/bootstrap/js/bootstrap.bundle.min.js"></script>
<script src="/plugins/toastr/toastr.min.js"></script>
<script src="/dist/js/adminlte.min.js"></script>
<script src="/assets/service.js"></script>
</body>
</html>
