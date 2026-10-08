# Neovarch Agent installer (Windows x64).
#
#   irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1 | iex
#
# Uninstall:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Maftuuh1922/neovrach_Agent/main/scripts/install.ps1))) -Uninstall
#
# Environment:
#   NEOVARCH_VERSION   release tag to install (e.g. v1.1.0). Default: latest.
#
# Installs per-user to %LOCALAPPDATA%\Programs\NeovarchAgent (no admin needed),
# adds Start Menu + Desktop shortcuts and a `neovarch` command on your PATH.

param(
    [switch]$Uninstall,
    [string]$Version = $env:NEOVARCH_VERSION
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar on
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$Repo        = 'Maftuuh1922/neovrach_Agent'
$ReleasesUrl = "https://github.com/$Repo/releases"
$Asset       = 'neovarch-agent-windows-x64.zip'
$AppName     = 'Neovarch Agent'
$ExeName     = 'NeovarchAgent.exe'

$Root       = Join-Path $env:LOCALAPPDATA 'Programs\NeovarchAgent'
$AppDir     = Join-Path $Root 'app'
$BinDir     = Join-Path $Root 'bin'
$Launcher   = Join-Path $BinDir 'neovarch.cmd'
$StartMenu  = $null
$DesktopLnk = $null
$programsDir = [Environment]::GetFolderPath('Programs')
$desktopDir  = [Environment]::GetFolderPath('Desktop')
if ($programsDir) { $StartMenu  = Join-Path $programsDir "$AppName.lnk" }
if ($desktopDir)  { $DesktopLnk = Join-Path $desktopDir "$AppName.lnk" }

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
    $lnk.Description = 'Autonomous AI agent'
    $lnk.Save()
}

function Stop-RunningApp {
    $procs = Get-Process -Name 'NeovarchAgent' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Step 'Closing the running Neovarch Agent'
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
    }
}

function Test-VcRuntime {
    $sys = Join-Path $env:SystemRoot 'System32'
    foreach ($dll in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') {
        if (-not (Test-Path (Join-Path $sys $dll))) { return $false }
    }
    return $true
}

function Confirm-VcRuntime {
    if (Test-VcRuntime) { Write-Ok 'Microsoft Visual C++ runtime found'; return }
    Write-Warn2 'Microsoft Visual C++ 2015-2022 runtime (x64) is missing. Neovarch Agent needs it to start.'
    $vcUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
    $answer = 'n'
    if ([Environment]::UserInteractive) {
        try { $answer = Read-Host '     Download and run the Microsoft installer now? [Y/n]' } catch { $answer = 'n' }
    }
    if ($answer -eq '' -or $answer -match '^(y|yes)$') {
        $vcExe = Join-Path $env:TEMP 'vc_redist.x64.exe'
        Write-Step "Downloading $vcUrl"
        Invoke-WebRequest -Uri $vcUrl -OutFile $vcExe -UseBasicParsing
        Write-Step 'Running the VC++ installer (Windows will ask for permission)'
        $p = Start-Process -FilePath $vcExe -ArgumentList '/install', '/passive', '/norestart' -Wait -PassThru
        Remove-Item $vcExe -Force -ErrorAction SilentlyContinue
        if (@(0, 1638, 3010) -contains $p.ExitCode) { Write-Ok 'VC++ runtime installed' }
        else { Write-Warn2 "VC++ installer exited with code $($p.ExitCode). Install it manually: $vcUrl" }
    } else {
        Write-Host "     Install it later from $vcUrl"
    }
}

function Invoke-Uninstall {
    Write-Banner
    Write-Step "Removing $AppName"
    Stop-RunningApp
    $removed = $false
    foreach ($f in @($StartMenu, $DesktopLnk) | Where-Object { $_ }) {
        if (Test-Path $f) { Remove-Item $f -Force; Write-Ok "removed $f"; $removed = $true }
    }
    Remove-FromUserPath $BinDir
    if (Test-Path $Root) { Remove-Item $Root -Recurse -Force; Write-Ok "removed $Root"; $removed = $true }
    Write-Host ''
    if ($removed) { Write-Host "$AppName uninstalled. Your chats and settings were left in place." }
    else { Write-Host "$AppName is not installed." }
}

function Invoke-Install {
    Write-Banner

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ($arch -eq 'x86') {
        Write-Host "$AppName for 32-bit Windows is not available yet. See $ReleasesUrl/latest"
        return
    }
    if ($arch -eq 'ARM64') {
        Write-Warn2 'No native ARM64 build yet; installing the x64 build (runs under Windows 11 x64 emulation).'
    }

    if ($Version) {
        if ($Version -notmatch '^v') { $Version = "v$Version" }
        $url = "$ReleasesUrl/download/$Version/$Asset"; $label = $Version
    } else {
        $url = "$ReleasesUrl/latest/download/$Asset"; $label = 'latest'
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("neovarch-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        Write-Step "Downloading $AppName ($label)"
        Write-Host "    $url" -ForegroundColor DarkGray
        $zip = Join-Path $tmp $Asset
        try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
        catch { Stop-WithError "download failed ($($_.Exception.Message)). Check the tag or see $ReleasesUrl" }

        Write-Step 'Unpacking'
        $unz = Join-Path $tmp 'x'
        Expand-Archive -Path $zip -DestinationPath $unz -Force
        $src = Join-Path $unz $AppName
        if (-not (Test-Path (Join-Path $src $ExeName))) {
            $exe = Get-ChildItem -Path $unz -Filter $ExeName -Recurse | Select-Object -First 1
            if (-not $exe) { Stop-WithError "archive layout unexpected (no $ExeName)" }
            $src = $exe.DirectoryName
        }

        Stop-RunningApp
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        if (Test-Path $AppDir) { Remove-Item $AppDir -Recurse -Force }
        Move-Item -Path $src -Destination $AppDir
        Write-Ok "installed to $AppDir"
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $exePath = Join-Path $AppDir $ExeName

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    $cmd = "@echo off`r`nstart `"`" `"%~dp0..\app\$ExeName`" %*`r`n"
    [IO.File]::WriteAllText($Launcher, $cmd, [Text.Encoding]::ASCII)
    Write-Ok "created $Launcher"
    Add-ToUserPath $BinDir

    try {
        if ($StartMenu)  { New-Shortcut $StartMenu $exePath $AppDir;  Write-Ok 'added Start Menu shortcut' }
        if ($DesktopLnk) { New-Shortcut $DesktopLnk $exePath $AppDir; Write-Ok 'added Desktop shortcut' }
    } catch { Write-Warn2 "could not create shortcuts: $($_.Exception.Message)" }

    Confirm-VcRuntime

    Write-Host ''
    Write-Host "$AppName is installed. " -NoNewline
    Write-Host 'Open it from the Start Menu, or run ' -NoNewline
    Write-Host 'neovarch' -ForegroundColor Red -NoNewline
    Write-Host ' in a new terminal.'
}

if ($Uninstall -or $env:NEOVARCH_UNINSTALL -eq '1') { Invoke-Uninstall } else { Invoke-Install }
