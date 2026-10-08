# Neovarch Agent installer (Windows x64) - installs the desktop app (Electron).
#
#   irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1 | iex
#
# Uninstall:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1))) -Uninstall
# Portable (zip, no installer):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1))) -Portable
#
# Environment:
#   NEOVARCH_VERSION    release tag to install (e.g. v1.2.1). Default: latest.
#   NEOVARCH_PORTABLE=1 same as -Portable.   NEOVARCH_UNINSTALL=1 same as -Uninstall.
#
# Default mode runs the NSIS installer silently, per user (no admin):
#   %LOCALAPPDATA%\Programs\Neovarch Agent, with Start Menu + Desktop shortcuts.
# Portable mode unpacks the zip to %LOCALAPPDATA%\Programs\NeovarchAgent\app.
# Both add a `neovarch` command (%LOCALAPPDATA%\Programs\NeovarchAgent\bin) to PATH.
#
# The Neovarch core (Hermes Agent, Python) is not installed here: on first
# launch the app offers to install it (Hermes Agent's own installer, pinned to
# the revision the app was built against) or to connect to an existing
# Hermes gateway. An existing `hermes` install is used as is.

param(
    [switch]$Uninstall,
    [switch]$Portable,
    [string]$Version = $env:NEOVARCH_VERSION
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar on
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$Repo         = 'Maftuuh1922/neovrach_Agent'
$ReleasesUrl  = "https://github.com/$Repo/releases"
$SetupAsset   = 'neovarch-agent-windows-x64-setup.exe'
$ZipAsset     = 'neovarch-agent-windows-x64.zip'
$AppName      = 'Neovarch Agent'
$ExeName      = 'Neovarch Agent.exe'
$ProcName     = 'Neovarch Agent'

$Root         = Join-Path $env:LOCALAPPDATA 'Programs\NeovarchAgent'   # bin (+ portable app)
$PortableDir  = Join-Path $Root 'app'
$BinDir       = Join-Path $Root 'bin'
$Launcher     = Join-Path $BinDir 'neovarch.cmd'
$InstallDir   = Join-Path $env:LOCALAPPDATA "Programs\$AppName"         # NSIS install dir
$Uninstaller  = Join-Path $InstallDir "Uninstall $AppName.exe"
$StartMenu    = $null
$DesktopLnk   = $null
$programsDir  = [Environment]::GetFolderPath('Programs')
$desktopDir   = [Environment]::GetFolderPath('Desktop')
if ($programsDir) { $StartMenu  = Join-Path $programsDir "$AppName.lnk" }
if ($desktopDir)  { $DesktopLnk = Join-Path $desktopDir "$AppName.lnk" }
if ($env:NEOVARCH_PORTABLE -eq '1') { $Portable = $true }

function Write-Banner { Write-Host ''; Write-Host $AppName -ForegroundColor Red -NoNewline; Write-Host ' installer' -ForegroundColor DarkGray; Write-Host '' }
function Write-Step($m) { Write-Host '==> ' -ForegroundColor Red -NoNewline; Write-Host $m }
function Write-Ok($m)   { Write-Host ' ok ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Write-Warn2($m){ Write-Host 'warn ' -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Stop-WithError($m) { Write-Host 'error ' -ForegroundColor Red -NoNewline; Write-Host $m; throw $m }

function Get-UserPath { $p = [Environment]::GetEnvironmentVariable('Path', 'User'); if ($null -eq $p) { '' } else { $p } }

function Add-ToUserPath($dir) {
    $parts = @((Get-UserPath) -split ';' | Where-Object { $_ -ne '' })
    if ($parts -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User')
        Write-Ok "added $dir to your user PATH"
    }
    if (@($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }
}

function Remove-FromUserPath($dir) {
    $parts = @((Get-UserPath) -split ';' | Where-Object { $_ -ne '' })
    if ($parts -contains $dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts | Where-Object { $_ -ne $dir }) -join ';'), 'User')
        Write-Ok "removed $dir from your user PATH"
    }
}

function New-Shortcut($path, $target, $workdir) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath = $target
    $lnk.WorkingDirectory = $workdir
    $lnk.IconLocation = "$target,0"
    $lnk.Description = 'Neovarch Agent desktop'
    $lnk.Save()
}

function Stop-RunningApp {
    # 'NeovarchAgent' is the 1.1.x (Flutter) process name.
    $procs = Get-Process -Name $ProcName, 'NeovarchAgent' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Step "Closing the running $AppName"
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1200
    }
}

function Remove-LegacyFlutterApp {
    # Neovarch Agent 1.1.x was a Flutter build unpacked to ...\NeovarchAgent\app.
    $legacyExe = Join-Path $PortableDir 'NeovarchAgent.exe'
    if (Test-Path $legacyExe) {
        Remove-Item $PortableDir -Recurse -Force
        Write-Ok 'removed the previous (1.1.x) desktop build'
    }
}

function Write-Launcher($exePath) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    $cmd = "@echo off`r`nstart `"`" `"$exePath`" %*`r`n"
    [IO.File]::WriteAllText($Launcher, $cmd, [Text.Encoding]::ASCII)
    Write-Ok "created $Launcher"
    Add-ToUserPath $BinDir
}

function Get-ReleaseUrl($asset) {
    if ($Version) {
        if ($Version -notmatch '^v') { $script:Version = "v$Version" }
        return @("$ReleasesUrl/download/$Version/$asset", $Version)
    }
    return @("$ReleasesUrl/latest/download/$asset", 'latest')
}

function Show-CoreNote {
    if (Get-Command hermes -ErrorAction SilentlyContinue) {
        Write-Ok 'Neovarch core (Hermes Agent) found'
    } else {
        Write-Host '    The Neovarch core (Hermes Agent) is not installed yet. On first launch the'
        Write-Host '    app offers to install it for you, or to connect to an existing gateway.'
    }
}

function Invoke-Uninstall {
    Write-Banner
    Write-Step "Removing $AppName"
    Stop-RunningApp
    $removed = $false
    if (Test-Path $Uninstaller) {
        $p = Start-Process -FilePath $Uninstaller -ArgumentList '/S' -Wait -PassThru
        if ($p.ExitCode -eq 0) { Write-Ok "ran $Uninstaller"; $removed = $true }
        else { Write-Warn2 "uninstaller exited with code $($p.ExitCode)" }
    }
    foreach ($f in @($StartMenu, $DesktopLnk) | Where-Object { $_ }) {
        if (Test-Path $f) { Remove-Item $f -Force; Write-Ok "removed $f"; $removed = $true }
    }
    Remove-FromUserPath $BinDir
    if (Test-Path $Root) { Remove-Item $Root -Recurse -Force; Write-Ok "removed $Root"; $removed = $true }
    Write-Host ''
    if ($removed) { Write-Host "$AppName uninstalled. Your chats, settings and the Neovarch core (Hermes Agent) were left in place." }
    else { Write-Host "$AppName is not installed." }
}

function Install-Setup($tmp) {
    $url, $label = Get-ReleaseUrl $SetupAsset
    Write-Step "Downloading $AppName installer ($label)"
    Write-Host "    $url" -ForegroundColor DarkGray
    $setup = Join-Path $tmp $SetupAsset
    try { Invoke-WebRequest -Uri $url -OutFile $setup -UseBasicParsing }
    catch { Stop-WithError "download failed ($($_.Exception.Message)). Check the tag or see $ReleasesUrl" }

    Stop-RunningApp
    Remove-LegacyFlutterApp
    Write-Step 'Installing (silent, per user)'
    # NSIS: /S = silent, /D= must be last and unquoted.
    $p = Start-Process -FilePath $setup -ArgumentList '/S', "/D=$InstallDir" -Wait -PassThru
    if ($p.ExitCode -ne 0) { Stop-WithError "installer exited with code $($p.ExitCode)" }
    $exePath = Join-Path $InstallDir $ExeName
    if (-not (Test-Path $exePath)) { Stop-WithError "installer finished but $exePath is missing" }
    Write-Ok "installed to $InstallDir"
    return $exePath
}

function Install-Portable($tmp) {
    $url, $label = Get-ReleaseUrl $ZipAsset
    Write-Step "Downloading $AppName ($label, portable zip)"
    Write-Host "    $url" -ForegroundColor DarkGray
    $zip = Join-Path $tmp $ZipAsset
    try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
    catch { Stop-WithError "download failed ($($_.Exception.Message)). Check the tag or see $ReleasesUrl" }

    Write-Step 'Unpacking'
    $unz = Join-Path $tmp 'x'
    Expand-Archive -Path $zip -DestinationPath $unz -Force
    $exe = Get-ChildItem -Path $unz -Filter $ExeName -Recurse | Select-Object -First 1
    if (-not $exe) { Stop-WithError "archive layout unexpected (no $ExeName)" }

    Stop-RunningApp
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    if (Test-Path $PortableDir) { Remove-Item $PortableDir -Recurse -Force }
    Move-Item -Path $exe.DirectoryName -Destination $PortableDir
    Write-Ok "installed to $PortableDir"

    $exePath = Join-Path $PortableDir $ExeName
    try {
        if ($StartMenu)  { New-Shortcut $StartMenu $exePath $PortableDir;  Write-Ok 'added Start Menu shortcut' }
        if ($DesktopLnk) { New-Shortcut $DesktopLnk $exePath $PortableDir; Write-Ok 'added Desktop shortcut' }
    } catch { Write-Warn2 "could not create shortcuts: $($_.Exception.Message)" }
    return $exePath
}

function Invoke-Install {
    Write-Banner

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ($arch -eq 'x86') {
        Write-Host "$AppName for 32-bit Windows is not available. See $ReleasesUrl/latest"
        return
    }
    if ($arch -eq 'ARM64') {
        Write-Warn2 'No native ARM64 build yet; installing the x64 build (runs under Windows 11 x64 emulation).'
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("neovarch-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        if ($Portable) { $exePath = Install-Portable $tmp } else { $exePath = Install-Setup $tmp }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Launcher $exePath
    Show-CoreNote

    Write-Host ''
    Write-Host "$AppName is installed. " -NoNewline
    Write-Host 'Open it from the Start Menu, or run ' -NoNewline
    Write-Host 'neovarch' -ForegroundColor Red -NoNewline
    Write-Host ' in a new terminal.'
}

if ($Uninstall -or $env:NEOVARCH_UNINSTALL -eq '1') { Invoke-Uninstall } else { Invoke-Install }
