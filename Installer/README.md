# StoreExplorer IIS Installer

Deploy WitsmlExplorer (StoreExplorer) as a sub-application of an existing IIS website
(`https://sdpauto1`), making the app available at:

| Component | URL |
|-----------|-----|
| Frontend (React SPA) | `https://sdpauto1/storeExplorer` |
| Backend API (.NET 8)  | `https://sdpauto1/storeExplorer-api` |

---

## Prerequisites – build machine

| Tool | Minimum version |
|------|----------------|
| .NET SDK | 8.0 |
| Node.js | 20 LTS |
| Yarn | 1.22+ |

## Prerequisites – IIS target machine

| Requirement | Notes |
|-------------|-------|
| Windows Server 2016+ or Windows 10+ | IIS enabled |
| [ASP.NET Core 8 Hosting Bundle](https://dotnet.microsoft.com/download/dotnet/8.0) | Includes the IIS module |
| [IIS URL Rewrite Module](https://www.iis.net/downloads/microsoft/url-rewrite) | Required for SPA client-side routing |
| Existing IIS website `sdpauto1` | Already bound to HTTPS on port 443 |

---

## Build the installer

Run on your development / CI machine from the **repo root**:

```powershell
cd Installer
.\Build-Installer.ps1
```

The script produces `Installer\dist\StoreExplorer-Installer.zip`.

Optional flags:

| Flag | Purpose |
|------|---------|
| `-OutputDir <path>` | Write the zip to a custom directory |
| `-SkipFrontend` | Skip the Yarn/Vite build (reuse an existing `dist/`) |
| `-SkipApi` | Skip `dotnet publish` (reuse an existing publish output) |

---

## Install on the IIS server

1. Copy `StoreExplorer-Installer.zip` to the target Windows server.
2. Extract to a temporary folder, e.g. `C:\Temp\StoreExplorer-Installer`.
3. Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
cd C:\Temp\StoreExplorer-Installer
.\Install-StoreExplorer.ps1
```

The script creates the app pool, IIS applications, copies files, and sets permissions.

### Custom parameters

```powershell
# Different site name or web root
.\Install-StoreExplorer.ps1 -SiteName "Default Web Site" -WebRoot "C:\inetpub\wwwroot"
```

---

## Configuration

After installation, review `C:\inetpub\wwwroot\sdpauto1\storeExplorer-api\appsettings.json`.
Key settings:

| Setting | Default | Notes |
|---------|---------|-------|
| `AllowedOrigin` | `https://sdpauto1` | Must match the site origin exactly |
| `OAuth2Enabled` | `false` | Set to `true` for Azure AD auth |
| `LogQueries` | `false` | Enable to log all WITSML XML queries |

---

## File layout (post-install)

```
C:\inetpub\wwwroot\sdpauto1\
  storeExplorer\          ← frontend static files
    index.html
    assets\
    web.config            ← SPA fallback rewrite rules
  storeExplorer-api\      ← .NET 8 API binaries
    WitsmlExplorer.Api.dll
    appsettings.json
    web.config            ← ASP.NET Core IIS module config
    logs\
```
