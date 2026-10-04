<#
.SYNOPSIS
    Builds a single-file RealRTCW XR installer.

.DESCRIPTION
    Rebuilds the VR asset .pk3, stages the VR binaries, packs them into a zip, compiles a
    small .NET stub, then appends the zip to the stub. The stub unpacks the files and runs
    Setup-RealRTCWXR.ps1, which puts the game data into place.

    The stub needs no third-party tool. csc.exe is part of Windows.

    Two bundles exist:

      Minimal   Ships the VR build only. The user supplies the RealRTCW and Return to
                Castle Wolfenstein data, from Steam or by hand. About 240 MB.

      Full      Also ships the RealRTCW data, which the mod author permits. The user then
                supplies only the Return to Castle Wolfenstein data. About 2.1 GB.

.PARAMETER Config
    Which Visual Studio configuration to package. Default is Release.

.PARAMETER Bundle
    Minimal, Full, or Both. Default is Minimal.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\Make-Package.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\Make-Package.ps1 -Bundle Both
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'Production')]
    [string]$Config = 'Release',

    [ValidateSet('Minimal', 'Full', 'Both')]
    [string]$Bundle = 'Minimal',

    [string]$OutDir,

    # Overrides the version read from code/qcommon/q_shared.h.
    [string]$Version,

    # Folder that holds the RealRTCW data for the Full bundle. Default: found in Steam.
    # Point it at either the RealRTCW folder or its Main folder.
    [string]$RealRtcwSource,

    # Reuse the existing z_zzzRealRTCWXR.pk3 instead of rebuilding it from z_zzzRealRTCWXR/.
    [switch]$SkipAssetPk3,

    # Keep the staging folder for inspection.
    [switch]$KeepStaging
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackagingDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot     = Split-Path -Parent $PackagingDir
$BuildDir     = Join-Path $RepoRoot ("code\RealRTCWXR\x64\{0}" -f $Config)
$BuildMain    = Join-Path $BuildDir 'Main'
$AssetsDir    = Join-Path $PackagingDir 'assets'

. (Join-Path $PackagingDir 'FileGroups.ps1')

function Write-Step { param([string]$m) Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Info { param([string]$m) Write-Host "    $m" }

function Get-SevenZip {
    foreach ($c in @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'))) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-Csc {
    $dirs = Get-ChildItem 'C:\Windows\Microsoft.NET\Framework64' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'v4.*' } |
            Sort-Object Name -Descending

    foreach ($d in $dirs) {
        $csc = Join-Path $d.FullName 'csc.exe'
        if (Test-Path -LiteralPath $csc) { return $csc }
    }
    return $null
}

function Get-ProductVersion {
    $header = Join-Path $RepoRoot 'code\qcommon\q_shared.h'
    $text = Get-Content -LiteralPath $header -Raw
    $m = [regex]::Match($text, '#define\s+REALRTCWXR_VERSION\s+"([^"]+)"')
    if (-not $m.Success) {
        throw "Cannot read REALRTCWXR_VERSION from $header. Pass -Version instead."
    }
    return $m.Groups[1].Value
}

# Finds the Main folder of a Steam game, using the same lookup the engine uses.
function Find-SteamGameMain {
    param([string]$AppId, [string]$SteamDir)

    $root = $null
    foreach ($k in @(
        @{ Path = 'HKCU:\Software\Valve\Steam';             Value = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Value = 'InstallPath' }
    )) {
        try { $p = (Get-ItemProperty -Path $k.Path -Name $k.Value -ErrorAction Stop).($k.Value) } catch { continue }
        if ($p -and (Test-Path -LiteralPath $p)) { $root = $p; break }
    }
    if (-not $root) { return $null }

    $libs = @($root)
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $text = Get-Content -LiteralPath $vdf -Raw
        foreach ($m in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
            $libs += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }

    foreach ($lib in $libs) {
        $acf = Join-Path $lib ("steamapps\appmanifest_{0}.acf" -f $AppId)
        $dir = $SteamDir
        if (Test-Path -LiteralPath $acf) {
            $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"installdir"\s*"([^"]+)"')
            if ($m.Success) { $dir = $m.Groups[1].Value -replace '\\\\', '\' }
        }

        $main = Join-Path $lib ("steamapps\common\{0}\Main" -f $dir)
        if (Test-Path -LiteralPath $main) { return $main }
    }

    return $null
}

function Copy-Required {
    param([string]$Source, [string]$Destination, [string]$Why)

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Missing input file: $Source`r`n    Needed for: $Why"
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Info ("staged   {0}" -f (Split-Path -Leaf $Source))
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0} GB" -f [math]::Round($Bytes / 1GB, 2)) }
    return ("{0} MB" -f [math]::Round($Bytes / 1MB, 2))
}

# ---------------------------------------------------------------------------

$sevenZip = Get-SevenZip
$csc      = Get-Csc
if (-not $csc) {
    throw "csc.exe was not found under C:\Windows\Microsoft.NET\Framework64. Install the .NET Framework 4 feature."
}
if (-not $sevenZip) {
    throw "7z.exe was not found. Install 7-Zip. Compress-Archive cannot build a package this large."
}

if (-not $Version) { $Version = Get-ProductVersion }
if (-not $OutDir)  { $OutDir  = Join-Path $RepoRoot 'dist' }

$bundles = if ($Bundle -eq 'Both') { @('Minimal', 'Full') } else { @($Bundle) }

Write-Host "RealRTCW XR package build"
Write-Host "-------------------------"
Write-Info "Repo:    $RepoRoot"
Write-Info "Config:  $Config"
Write-Info "Version: $Version"
Write-Info "Bundles: $($bundles -join ', ')"
Write-Info "7-Zip:   $sevenZip"
Write-Info "csc:     $csc"

if (-not (Test-Path -LiteralPath $BuildDir)) {
    throw "The build output folder is absent: $BuildDir`r`n    Build the $Config configuration of code\RealRTCWXR\RealRTCWXR.sln first."
}

# --- Locate the RealRTCW data once, if any bundle needs it ------------------
$realRtcwMain = $null
if ($bundles -contains 'Full') {
    Write-Step "Locate the RealRTCW data for the Full bundle"

    if ($RealRtcwSource) {
        $candidate = $RealRtcwSource.TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $candidate 'Main')) { $candidate = Join-Path $candidate 'Main' }
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "-RealRtcwSource does not exist: $RealRtcwSource"
        }
        $realRtcwMain = $candidate
    } else {
        $group = $FileGroups | Where-Object { $_.Key -eq 'RealRTCW' }
        $realRtcwMain = Find-SteamGameMain -AppId $group.AppId -SteamDir $group.SteamDir
        if (-not $realRtcwMain) {
            throw ("The RealRTCW data was not found in any Steam library.`r`n" +
                   "    Install RealRTCW through Steam, or pass -RealRtcwSource <path to the RealRTCW folder>.")
        }
    }

    Write-Info "Source: $realRtcwMain"
}

$outputs = @()

foreach ($variant in $bundles) {
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("RealRTCWXR-pkg-" + [System.Guid]::NewGuid().ToString('N'))
    $stage       = Join-Path $stagingRoot 'payload'
    $stageMain   = Join-Path $stage 'Main'
    New-Item -ItemType Directory -Path $stageMain -Force | Out-Null

    try {
        Write-Host ""
        Write-Host ("### {0} bundle" -f $variant) -ForegroundColor Yellow

        # --- VR asset pk3 ----------------------------------------------------
        Write-Step "Build z_zzzRealRTCWXR.pk3"
        $assetSrcDir = Join-Path $RepoRoot 'z_zzzRealRTCWXR'
        $assetPk3    = Join-Path $stageMain 'z_zzzRealRTCWXR.pk3'

        if ($SkipAssetPk3) {
            Copy-Required (Join-Path $BuildMain 'z_zzzRealRTCWXR.pk3') $assetPk3 'VR menus, shaders and .weap overrides'
        } else {
            # -tzip because the engine reads .pk3 as a plain zip.
            & $sevenZip a -tzip -mx=9 -bso0 -bsp0 $assetPk3 (Join-Path $assetSrcDir '*') | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to build $assetPk3" }
            Write-Info ("built    z_zzzRealRTCWXR.pk3 from {0}" -f $assetSrcDir)
        }

        # --- VR binaries -----------------------------------------------------
        Write-Step "Stage the VR binaries from $Config"
        Copy-Required (Join-Path $BuildDir 'RealRTCWXR.exe')              $stage 'the game executable'
        Copy-Required (Join-Path $BuildDir 'renderer_sp_rend2_xr_64.dll') $stage 'the VR renderer'
        Copy-Required (Join-Path $BuildMain 'cgame_sp_xr_64.dll')         $stageMain 'the client game module'
        Copy-Required (Join-Path $BuildMain 'qagame_sp_xr_64.dll')        $stageMain 'the server game module'
        Copy-Required (Join-Path $BuildMain 'ui_sp_xr_64.dll')            $stageMain 'the menu module'

        # Taken from code/libs so the package does not depend on stale copies in the build folder.
        Copy-Required (Join-Path $RepoRoot 'code\libs\win64\SDL264.dll')   $stage 'window and input support'
        Copy-Required (Join-Path $RepoRoot 'code\libs\win64\OpenAL64.dll') $stage 'audio support'

        # --- Prebuilt VR asset pk3 files -------------------------------------
        Write-Step "Stage the prebuilt VR assets"
        $prebuiltAssets = @(
            @{ Name = 'z_realrtcw_models_hands_vr.pk3';        Why = 'the VR hand models' },
            @{ Name = 'z_zzzz_remastered_digitaldeluxe_3.pk3'; Why = 'the VR modified weapon models and textures' }
        )

        foreach ($a in $prebuiltAssets) {
            $src = Join-Path $AssetsDir $a.Name
            if (-not (Test-Path -LiteralPath $src)) {
                $src = Join-Path $BuildMain $a.Name
                Write-Info "packaging\assets\$($a.Name) is absent. Using the copy in the build folder."
                Write-Info "Copy it into packaging\assets to make this build reproducible."
            }
            Copy-Required $src $stageMain $a.Why
        }

        # --- Bundled game data -----------------------------------------------
        $bundledGroups = @()
        if ($variant -eq 'Full') {
            $group = $FileGroups | Where-Object { $_.Key -eq 'RealRTCW' }
            Write-Step "Stage the RealRTCW data"

            $absent = @()
            foreach ($f in $group.Files) {
                if ($f.ContainsKey('Redistribute') -and -not $f.Redistribute) {
                    Write-Info ("excluded {0} (not ours to redistribute)" -f $f.Name)
                    continue
                }

                $src = Join-Path $realRtcwMain $f.Name
                if (-not (Test-Path -LiteralPath $src)) {
                    if ($f.Required) { $absent += $f.Name } else { Write-Info ("skipped  {0} (optional, not installed)" -f $f.Name) }
                    continue
                }
                Copy-Item -LiteralPath $src -Destination $stageMain -Force
                Write-Info ("staged   {0}" -f $f.Name)
            }

            if ($absent.Count -gt 0) {
                throw ("These required RealRTCW files were not found in {0}:`r`n    {1}" -f $realRtcwMain, ($absent -join "`r`n    "))
            }

            $bundledGroups = @('RealRTCW')
        }

        # --- Installer support files ------------------------------------------
        Write-Step "Stage the setup files"
        Copy-Required (Join-Path $PackagingDir 'Setup-RealRTCWXR.ps1') $stage 'the game data setup step'
        Copy-Required (Join-Path $PackagingDir 'FileGroups.ps1')       $stage 'the shared game data lists'
        Copy-Required (Join-Path $PackagingDir 'README-FIRST.txt')     $stage 'the user instructions'
        Copy-Required (Join-Path $RepoRoot 'COPYING.txt')              $stage 'the licence'

        $manifest = [pscustomobject]@{
            Product       = 'RealRTCW XR'
            Version       = $Version
            Config        = $Config
            Bundle        = $variant
            BundledGroups = $bundledGroups
        }
        $manifestPath = Join-Path $stage 'package-manifest.json'
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        Write-Info "staged   package-manifest.json"

        # --- Payload zip -------------------------------------------------------
        Write-Step "Pack the payload"
        $payload = Join-Path $stagingRoot 'payload.zip'

        # .pk3 files are already deflate archives, so store them. Recompressing costs
        # minutes and saves nothing.
        & $sevenZip a -tzip -mx=9 -bso0 -bsp0 "-xr!*.pk3" $payload (Join-Path $stage '*') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to build $payload" }

        & $sevenZip a -tzip -mx=0 -bso0 -bsp0 -r $payload (Join-Path $stage '*.pk3') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to add the .pk3 files to $payload" }

        $payloadLength = (Get-Item -LiteralPath $payload).Length
        Write-Info ("payload.zip is {0}." -f (Format-Size $payloadLength))

        # --- Compile the stub ---------------------------------------------------
        Write-Step "Compile the installer stub"
        $dataNeeded = if ($variant -eq 'Full') {
            'The RealRTCW data is included. It then needs the game data from Return to Castle Wolfenstein.'
        } else {
            'It then needs the game data from Return to Castle Wolfenstein and RealRTCW.'
        }
        $stubSrc = (Get-Content -LiteralPath (Join-Path $PackagingDir 'Stub\Installer.cs') -Raw).Replace('@@VERSION@@', $Version).Replace('@@DATA_NEEDED@@', $dataNeeded)
        $stubCs  = Join-Path $stagingRoot 'Installer.cs'
        [System.IO.File]::WriteAllText($stubCs, $stubSrc, (New-Object System.Text.UTF8Encoding($false)))

        # csc derives the exe's version resource from these attributes.
        $shortVersion = ($Version -split '-')[0]
        $asmInfo = @"
using System.Reflection;
[assembly: AssemblyTitle("RealRTCW XR Setup")]
[assembly: AssemblyProduct("RealRTCW XR")]
[assembly: AssemblyDescription("Installs RealRTCW XR and puts the game data into place.")]
[assembly: AssemblyVersion("$shortVersion.0")]
[assembly: AssemblyFileVersion("$shortVersion.0")]
"@
        $asmCs = Join-Path $stagingRoot 'AssemblyInfo.cs'
        [System.IO.File]::WriteAllText($asmCs, $asmInfo, (New-Object System.Text.UTF8Encoding($false)))

        $stubExe = Join-Path $stagingRoot 'stub.exe'
        $refDir  = Split-Path -Parent $csc
        & $csc @(
            '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
            ('/out:' + $stubExe),
            ('/win32manifest:' + (Join-Path $PackagingDir 'Stub\Installer.manifest')),
            ('/reference:' + (Join-Path $refDir 'System.dll')),
            ('/reference:' + (Join-Path $refDir 'System.Drawing.dll')),
            ('/reference:' + (Join-Path $refDir 'System.Windows.Forms.dll')),
            ('/reference:' + (Join-Path $refDir 'System.IO.Compression.dll')),
            ('/reference:' + (Join-Path $refDir 'System.IO.Compression.FileSystem.dll')),
            $stubCs, $asmCs
        )
        if ($LASTEXITCODE -ne 0) { throw "csc.exe failed with exit code $LASTEXITCODE." }

        # --- Append the payload -------------------------------------------------
        # A .NET managed resource cannot hold a payload this large, so the zip goes
        # after the PE image. Footer: [int64 zip length][8 byte magic].
        Write-Step "Append the payload to the stub"
        if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
        $outExe = Join-Path $OutDir ("RealRTCWXR-{0}-{1}-{2}-Setup.exe" -f $Version, $Config, $variant)

        Copy-Item -LiteralPath $stubExe -Destination $outExe -Force

        $out = [System.IO.File]::Open($outExe, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
        try {
            $in = [System.IO.File]::OpenRead($payload)
            try { $in.CopyTo($out, 1MB) } finally { $in.Dispose() }

            $out.Write([System.BitConverter]::GetBytes([int64]$payloadLength), 0, 8)
            $out.Write([System.Text.Encoding]::ASCII.GetBytes('RTCWXRP1'), 0, 8)
        } finally {
            $out.Dispose()
        }

        $outputs += [pscustomobject]@{
            Bundle = $variant
            Path   = $outExe
            Size   = (Get-Item -LiteralPath $outExe).Length
        }
    }
    finally {
        if ($KeepStaging) {
            Write-Info "Staging kept at $stagingRoot"
        } elseif (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ""
Write-Host "Packages built." -ForegroundColor Green
foreach ($o in $outputs) {
    Write-Info ("{0,-8} {1}  ({2})" -f $o.Bundle, $o.Path, (Format-Size $o.Size))
}
