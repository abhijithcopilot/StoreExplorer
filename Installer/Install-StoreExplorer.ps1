<#
.SYNOPSIS
    Installs StoreExplorer into an existing IIS website (https://sdpauto1).

.DESCRIPTION
    This script:
      - Creates the IIS Application Pool "StoreExplorerApiPool" (No Managed Code).
      - Creates the IIS application "storeExplorer"     under the existing website for the frontend.
      - Creates the IIS application "storeExplorer-api" under the existing website for the .NET API.
      - Copies the built frontend and API files to the target directories.
      - Sets required NTFS permissions so IIS can read and write.
      - Optionally restarts the IIS site.

    Run this script as Administrator on the target IIS machine after extracting
    StoreExplorer-Installer.zip.

.PARAMETER SiteName
    Name of the existing IIS website to add the applications to.
    Default: "sdpauto1"

.PARAMETER WebRoot
    Root path of the IIS website on disk.
    Default: C:\inetpub\wwwroot\sdpauto1

.PARAMETER AppPoolName
    Name for the new IIS Application Pool for the API.
    Default: StoreExplorerApiPool

.PARAMETER DotNetVersion
    .NET CLR version for the app pool ("" = No Managed Code).
    Default: "" (correct for ASP.NET Core)

.EXAMPLE
    # Basic install with defaults
    .\Install-StoreExplorer.ps1

    # Custom site name / webroot
    .\Install-StoreExplorer.ps1 -SiteName "Default Web Site" -WebRoot "C:\inetpub\wwwroot"
#>

[CmdletBinding()]
param(
    [string]$SiteName    = "sdpauto1",
    [string]$WebRoot     = "C:\inetpub\wwwroot\sdpauto1",
    [string]$AppPoolName = "StoreExplorerApiPool",
    [string]$DotNetVersion = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Must run as administrator
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Please run this script as Administrator."
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Assert-Module([string]$name) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        Write-Error "PowerShell module '$name' not found. Ensure IIS Management Tools are installed."
    }
}

# ---------------------------------------------------------------------------
# Locate files relative to this script
# ---------------------------------------------------------------------------
$scriptDir   = $PSScriptRoot
$frontendSrc = Join-Path $scriptDir "frontend"
$apiSrc      = Join-Path $scriptDir "api"

foreach ($required in @($frontendSrc, $apiSrc)) {
    if (-not (Test-Path $required)) {
        Write-Error "Expected directory '$required' not found. Ensure you unzipped the full installer package."
    }
}

# ---------------------------------------------------------------------------
# Check IIS prerequisites
# ---------------------------------------------------------------------------
Write-Step "Checking prerequisites"

Assert-Module "WebAdministration"
Import-Module WebAdministration

# Check ASP.NET Core Hosting Bundle
$hostingBundle = Get-Command "dotnet" -ErrorAction SilentlyContinue
if (-not $hostingBundle) {
    Write-Warning @"
'dotnet' not found in PATH. 
The ASP.NET Core Runtime / Hosting Bundle must be installed on this machine.
Download from: https://dotnet.microsoft.com/download/dotnet/8.0
"@
}

# Check URL Rewrite Module (needed for SPA fallback)
$rewriteModule = Get-Item "IIS:\Sites" -ErrorAction SilentlyContinue
$rewriteDll = "$env:SystemRoot\System32\inetsrv\rewrite.dll"
if (-not (Test-Path $rewriteDll)) {
    Write-Warning @"
IIS URL Rewrite Module not detected at $rewriteDll.
The SPA client-side routing fallback will not work without it.
Download from: https://www.iis.net/downloads/microsoft/url-rewrite
"@
}

# Verify the target IIS site exists
if (-not (Get-WebSite -Name $SiteName -ErrorAction SilentlyContinue)) {
    Write-Error "IIS site '$SiteName' not found. Please create it first or specify -SiteName."
}

Write-Host "  Target IIS site : $SiteName" -ForegroundColor Green
Write-Host "  Web root        : $WebRoot"

# ---------------------------------------------------------------------------
# Create target directories
# ---------------------------------------------------------------------------
Write-Step "Creating target directories"

$frontendDest = Join-Path $WebRoot "storeExplorer"
$apiDest      = Join-Path $WebRoot "storeExplorer-api"
$apiLogsDir   = Join-Path $apiDest "logs"

foreach ($dir in @($frontendDest, $apiDest, $apiLogsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
        Write-Host "  Created: $dir"
    } else {
        Write-Host "  Exists : $dir"
    }
}

# ---------------------------------------------------------------------------
# Copy files
# ---------------------------------------------------------------------------
Write-Step "Copying frontend files → $frontendDest"
Copy-Item "$frontendSrc\*" $frontendDest -Recurse -Force

Write-Step "Copying API files → $apiDest"
Copy-Item "$apiSrc\*" $apiDest -Recurse -Force

# ---------------------------------------------------------------------------
# Configure IIS Application Pool for the API
# ---------------------------------------------------------------------------
Write-Step "Configuring Application Pool '$AppPoolName'"

if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
    Write-Host "  Created app pool: $AppPoolName"
} else {
    Write-Host "  App pool already exists: $AppPoolName"
}

# ASP.NET Core uses "No Managed Code"
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value $DotNetVersion
# Run as ApplicationPoolIdentity (default – least privilege)
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "processModel.identityType" -Value "ApplicationPoolIdentity"
# Enable 64-bit
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "enable32BitAppOnWin64" -Value $false

Write-Host "  App pool configured."

# ---------------------------------------------------------------------------
# Create / update IIS Applications
# ---------------------------------------------------------------------------
Write-Step "Creating IIS applications under '$SiteName'"

# Frontend (static files – uses the site's default app pool which serves static content)
$frontendAppPath = "/storeExplorer"
if (-not (Get-WebApplication -Site $SiteName -Name "storeExplorer" -ErrorAction SilentlyContinue)) {
    New-WebApplication -Site $SiteName -Name "storeExplorer" -PhysicalPath $frontendDest | Out-Null
    Write-Host "  Created: $SiteName$frontendAppPath → $frontendDest"
} else {
    Set-WebConfigurationProperty -Filter "system.applicationHost/sites/site[@name='$SiteName']/application[@path='$frontendAppPath']/virtualDirectory[@path='/']" `
        -Name "physicalPath" -Value $frontendDest
    Write-Host "  Updated: $SiteName$frontendAppPath → $frontendDest"
}

# API (ASP.NET Core)
$apiAppPath = "/storeExplorer-api"
if (-not (Get-WebApplication -Site $SiteName -Name "storeExplorer-api" -ErrorAction SilentlyContinue)) {
    New-WebApplication -Site $SiteName -Name "storeExplorer-api" -PhysicalPath $apiDest -ApplicationPool $AppPoolName | Out-Null
    Write-Host "  Created: $SiteName$apiAppPath → $apiDest (pool: $AppPoolName)"
} else {
    Set-WebConfigurationProperty -Filter "system.applicationHost/sites/site[@name='$SiteName']/application[@path='$apiAppPath']/virtualDirectory[@path='/']" `
        -Name "physicalPath" -Value $apiDest
    Set-ItemProperty "IIS:\Sites\$SiteName\storeExplorer-api" -Name "applicationPool" -Value $AppPoolName
    Write-Host "  Updated: $SiteName$apiAppPath → $apiDest (pool: $AppPoolName)"
}

# ---------------------------------------------------------------------------
# Set NTFS permissions
# ---------------------------------------------------------------------------
Write-Step "Setting NTFS permissions"

# IIS_IUSRS needs Read on the frontend (static files)
# IIS AppPool identity needs Modify on the API folder (logs, LiteDB)
$appPoolAccount = "IIS AppPool\$AppPoolName"
$iisUsrs        = "IIS_IUSRS"

function Grant-Permission([string]$path, [string]$account, [string]$rights) {
    $acl  = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $account, $rights, "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $path $acl
    Write-Host "  $rights → $account on $path"
}

Grant-Permission $frontendDest $iisUsrs        "ReadAndExecute"
Grant-Permission $apiDest      $appPoolAccount "Modify"

# ---------------------------------------------------------------------------
# Write a minimal appsettings override reminder
# ---------------------------------------------------------------------------
$apiSettingsPath = Join-Path $apiDest "appsettings.json"
Write-Host @"

  API settings file: $apiSettingsPath
  Review AllowedOrigin, OAuth2Enabled, and connection strings before first use.
"@ -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# Recycle app pool / restart site
# ---------------------------------------------------------------------------
Write-Step "Restarting Application Pool '$AppPoolName'"
Restart-WebAppPool -Name $AppPoolName
Write-Host "  App pool recycled."

Write-Step "Installation complete"
Write-Host @"

  Frontend : https://sdpauto1/storeExplorer
  API      : https://sdpauto1/storeExplorer-api

Troubleshooting
---------------
- If pages return 404, verify the IIS URL Rewrite module is installed.
- If the API returns 502, check the ASP.NET Core Hosting Bundle version (requires .NET 8).
- Logs are written to: $apiLogsDir
- To tail logs:  Get-Content "$apiLogsDir\api-*.log" -Wait -Tail 50
"@ -ForegroundColor Green
