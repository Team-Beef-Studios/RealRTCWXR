<#
.SYNOPSIS
    Puts the Return to Castle Wolfenstein and RealRTCW game data into a RealRTCW XR
    install folder.

.DESCRIPTION
    The installer stub unpacks the RealRTCW XR binaries, then runs this script.

    In the default mode the script finds the Steam libraries, checks that RealRTCW sits on
    a 5.0 beta branch, and copies the .pk3 and .cfg files that the VR build needs into
    <InstallRoot>\Main.

    With -ManualData the script does not touch Steam. It lists the files that are still
    absent and names the folder to copy them into. Use this mode if you own the games on
    GOG, on disc, or anywhere other than Steam.

    The full installer already carries the RealRTCW data. package-manifest.json records
    that, and this script then asks only for the Return to Castle Wolfenstein files.

    You can run this script by hand at any time to repair an install.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Setup-RealRTCWXR.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Setup-RealRTCWXR.ps1 -ManualData
#>
[CmdletBinding()]
param(
    [string]$InstallRoot,

    # Do not use Steam. List the files the user must copy in, then stop.
    [switch]$ManualData,

    # Accept the installed RealRTCW even if it is not on a 5.0 beta branch.
    [switch]$SkipVersionCheck,

    # Put a RealRTCW XR shortcut on the desktop once the install succeeds.
    [switch]$CreateShortcut
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# Exit codes. The installer stub reads these.
$EXIT_OK          = 0
$EXIT_ERROR       = 1
$EXIT_NEEDS_FILES = 2

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Steam beta branch names that carry RealRTCW 5.0. Add new names here.
$AllowedBetaKeys = @('realrtcw5.0*')

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$fileGroupsPath = Join-Path $scriptDir 'FileGroups.ps1'
if (-not (Test-Path -LiteralPath $fileGroupsPath)) {
    Write-Host "SETUP FAILED"
    Write-Host "------------"
    Write-Host "FileGroups.ps1 is absent from $scriptDir. The unpack is incomplete."
    exit 1
}
. $fileGroupsPath

# Files the installer itself unpacks. Their absence means a broken unpack.
$VrFiles = @(
    'RealRTCWXR.exe',
    'renderer_sp_rend2_xr_64.dll',
    'SDL264.dll',
    'OpenAL64.dll',
    'Main\cgame_sp_xr_64.dll',
    'Main\qagame_sp_xr_64.dll',
    'Main\ui_sp_xr_64.dll',
    'Main\z_zzzRealRTCWXR.pk3',
    'Main\z_realrtcw_models_hands_vr.pk3',
    'Main\z_zzzz_remastered_digitaldeluxe_3.pk3'
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step { param([string]$m) Write-Host ""; Write-Host "==> $m" }
function Write-Info { param([string]$m) Write-Host "    $m" }
function Write-Warn { param([string]$m) Write-Host "    WARNING: $m" }

function Get-BundledGroups {
    param([string]$Root)

    $manifest = Join-Path $Root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifest)) { return @() }

    try {
        $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    } catch {
        Write-Warn "package-manifest.json is unreadable. Treating every group as absent."
        return @()
    }

    if ($data.PSObject.Properties.Name -contains 'BundledGroups' -and $data.BundledGroups) {
        return @($data.BundledGroups)
    }
    return @()
}

function Get-SteamRoot {
    $keys = @(
        @{ Path = 'HKCU:\Software\Valve\Steam';             Value = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Value = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam';             Value = 'InstallPath' }
    )

    foreach ($k in $keys) {
        try {
            $p = (Get-ItemProperty -Path $k.Path -Name $k.Value -ErrorAction Stop).($k.Value)
        } catch {
            continue
        }
        if ($p -and (Test-Path -LiteralPath $p)) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }

    return $null
}

function Get-SteamLibraries {
    param([string]$SteamRoot)

    $libs = New-Object System.Collections.Generic.List[string]
    $libs.Add($SteamRoot)

    $vdf = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $vdf)) {
        Write-Warn "libraryfolders.vdf is absent. Only the main Steam folder is searched."
        return , $libs.ToArray()
    }

    $text = Get-Content -LiteralPath $vdf -Raw

    # Steam >= 2021 writes "path" keys. Older clients write "1" "D:\\SteamLibrary".
    $hits = [regex]::Matches($text, '"path"\s*"([^"]+)"')
    if ($hits.Count -eq 0) {
        $hits = [regex]::Matches($text, '"\d+"\s*"([A-Za-z]:[^"]+)"')
    }

    foreach ($m in $hits) {
        $p = $m.Groups[1].Value -replace '\\\\', '\'
        if ((Test-Path -LiteralPath $p) -and -not ($libs -contains $p)) {
            $libs.Add($p)
        }
    }

    # The comma stops PowerShell from unrolling the list into the pipeline.
    return , $libs.ToArray()
}

function Get-SteamApp {
    param(
        [string[]]$Libraries,
        [string]$AppId
    )

    foreach ($lib in $Libraries) {
        $acf = Join-Path $lib ("steamapps\appmanifest_{0}.acf" -f $AppId)
        if (-not (Test-Path -LiteralPath $acf)) { continue }

        $text = Get-Content -LiteralPath $acf -Raw

        $installDir = $null
        $m = [regex]::Match($text, '"installdir"\s*"([^"]+)"')
        if ($m.Success) { $installDir = $m.Groups[1].Value -replace '\\\\', '\' }
        if (-not $installDir) { continue }

        $path = Join-Path $lib ("steamapps\common\{0}" -f $installDir)
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $betaKey = ''
        $m = [regex]::Match($text, '"BetaKey"\s*"([^"]+)"', 'IgnoreCase')
        if ($m.Success) { $betaKey = $m.Groups[1].Value }

        $buildId = ''
        $m = [regex]::Match($text, '"buildid"\s*"([^"]+)"', 'IgnoreCase')
        if ($m.Success) { $buildId = $m.Groups[1].Value }

        return [pscustomobject]@{
            AppId   = $AppId
            Path    = $path
            BetaKey = $betaKey
            BuildId = $buildId
        }
    }

    return $null
}

function Test-BetaKey {
    param([string]$BetaKey)

    foreach ($pattern in $AllowedBetaKeys) {
        if ($BetaKey -like $pattern) { return $true }
    }
    return $false
}

function Get-BetaBranchHelp {
    param([string]$BetaKey)

    return @(
        "RealRTCW is not on a 5.0 beta branch.",
        "",
        "    Installed branch: $(if ($BetaKey) { $BetaKey } else { '(default)' })",
        "    Needed branch:    $($AllowedBetaKeys -join ', ')",
        "",
        "    To change the branch:",
        "      1. Open the Steam library.",
        "      2. Right-click RealRTCW, then choose Properties.",
        "      3. Open the Betas tab.",
        "      4. Choose the 5.0 beta from the list.",
        "      5. Let Steam finish the update.",
        "      6. Run this setup again."
    ) -join "`r`n"
}

function Copy-GameFile {
    param([string]$SourceDir, [string]$DestDir, [string]$Name)

    $src = Join-Path $SourceDir $Name
    if (-not (Test-Path -LiteralPath $src)) { return 'missing' }

    $dst = Join-Path $DestDir $Name
    if (Test-Path -LiteralPath $dst) {
        $s = Get-Item -LiteralPath $src
        $d = Get-Item -LiteralPath $dst
        if ($s.Length -eq $d.Length -and $s.LastWriteTimeUtc -eq $d.LastWriteTimeUtc) {
            return 'current'
        }
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    return 'copied'
}

function New-DesktopShortcut {
    param([string]$Root)

    $exe = Join-Path $Root 'RealRTCWXR.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Warn "RealRTCWXR.exe is absent. The setup made no shortcut."
        return
    }

    # DesktopDirectory follows a desktop that OneDrive or a policy moved.
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
        Write-Warn "The desktop folder was not found. The setup made no shortcut."
        return
    }

    $link = Join-Path $desktop 'RealRTCW XR.lnk'
    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($link)
        $sc.TargetPath = $exe
        $sc.WorkingDirectory = $Root
        $sc.IconLocation = "$exe,0"
        $sc.Description = 'RealRTCW XR'
        $sc.Save()
        Write-Info "Desktop shortcut: $link"
    } catch {
        Write-Warn "The setup could not make the desktop shortcut: $($_.Exception.Message)"
    } finally {
        if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}

# Required files of a group that are not yet in the Main folder.
function Get-AbsentFiles {
    param([hashtable]$Group, [string]$MainDir)

    $absent = @()
    foreach ($f in $Group.Files) {
        if (-not $f.Required) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $MainDir $f.Name))) { $absent += $f.Name }
    }
    return , $absent
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    if (-not $InstallRoot) {
        $InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $InstallRoot = $InstallRoot.TrimEnd('\')
    $mainDir = Join-Path $InstallRoot 'Main'

    Write-Host "RealRTCW XR data setup"
    Write-Host "----------------------"
    Write-Info "Install folder: $InstallRoot"

    if (-not (Test-Path -LiteralPath $mainDir)) {
        New-Item -ItemType Directory -Path $mainDir | Out-Null
    }

    # The @() guards against PowerShell unrolling an empty result to $null.
    $bundled = @(Get-BundledGroups -Root $InstallRoot)

    # A bundled group still has files the package is not allowed to carry, such as paid
    # DLC. Those come from the player's own Steam install, and only if they own them.
    $needed = @()
    foreach ($g in $FileGroups) {
        if ($bundled -contains $g.Key) {
            $fetch = @($g.Files | Where-Object { $_.ContainsKey('Redistribute') -and -not $_.Redistribute })
            $extrasOnly = $true
        } else {
            $fetch = @($g.Files)
            $extrasOnly = $false
        }

        if ($fetch.Count -gt 0) {
            $needed += @{ Group = $g; Files = $fetch; ExtrasOnly = $extrasOnly }
        }
    }

    if ($bundled.Count -gt 0) {
        Write-Info "This installer already carries the data for: $($bundled -join ', ')"
    }

    if ($needed.Count -eq 0) {
        Write-Info "No further game data is needed."
    } else {
        Write-Info "Game data still needed from: $(($needed | ForEach-Object { $_.Group.AppName }) -join ', ')"
    }

    # --- Manual mode ---------------------------------------------------------
    if ($ManualData) {
        Write-Step "Check the game data that you provide"

        $pending = @()
        foreach ($entry in $needed) {
            $g = $entry.Group
            if ($entry.ExtrasOnly) { continue }
            $absent = Get-AbsentFiles -Group $g -MainDir $mainDir
            if ($absent.Count -gt 0) {
                $pending += ,@{ Group = $g; Absent = $absent }
            } else {
                Write-Info "$($g.AppName): all files are present."
            }
        }

        if ($pending.Count -gt 0) {
            Write-Host ""
            Write-Host "ACTION NEEDED"
            Write-Host "-------------"
            Write-Host "Copy the files below into this folder:"
            Write-Host ""
            Write-Host "    $mainDir"
            Write-Host ""

            foreach ($p in $pending) {
                Write-Host "From $($p.Group.SourceHint):"
                foreach ($n in $p.Absent) { Write-Host "    $n" }
                Write-Host ""
            }

            Write-Host "Copy the files, then press Install again."
            Write-Host "Do not rename the files. Do not unpack them."
            exit $EXIT_NEEDS_FILES
        }

        Write-Info "Every required file is present."
    }
    # --- Steam mode ----------------------------------------------------------
    elseif ($needed.Count -gt 0) {
        Write-Step "Find Steam"
        $steamRoot = Get-SteamRoot
        if (-not $steamRoot) {
            throw "Steam is not installed, or its registry entry is absent.`r`n    Install Steam, or run the setup again and choose `"I will provide the game files myself`"."
        }
        Write-Info "Steam: $steamRoot"

        $libraries = Get-SteamLibraries -SteamRoot $steamRoot
        foreach ($l in $libraries) { Write-Info "Library: $l" }

        $missing = @()

        foreach ($entry in $needed) {
            $g = $entry.Group

            Write-Step "Find $($g.AppName) (app $($g.AppId))"
            $app = Get-SteamApp -Libraries $libraries -AppId $g.AppId
            if (-not $app) {
                if ($entry.ExtrasOnly) {
                    # Only optional extras were wanted here, such as paid DLC that the
                    # package is not allowed to carry. Not owning it is normal.
                    Write-Info "$($g.AppName) is not installed through Steam. The optional extras are skipped."
                    continue
                }
                throw "$($g.AppName) is not installed through Steam.`r`n    Install it from $($g.StoreUrl), or run the setup again and choose `"I will provide the game files myself`"."
            }

            Write-Info "Path:     $($app.Path)"
            if ($g.CheckBeta -and -not $entry.ExtrasOnly) {
                Write-Info "Branch:   $(if ($app.BetaKey) { $app.BetaKey } else { '(none - default branch)' })"
                Write-Info "Build id: $($app.BuildId)"

                if (-not (Test-BetaKey -BetaKey $app.BetaKey)) {
                    $help = Get-BetaBranchHelp -BetaKey $app.BetaKey
                    if ($SkipVersionCheck) {
                        Write-Warn "The branch check failed, but -SkipVersionCheck was given. The game may not start."
                        Write-Host $help
                    } else {
                        throw $help
                    }
                } else {
                    Write-Info "Branch check passed."
                }
            }

            $sourceMain = Join-Path $app.Path 'Main'
            if (-not (Test-Path -LiteralPath $sourceMain)) {
                if ($entry.ExtrasOnly) {
                    Write-Info "The $($g.AppName) Main folder is absent. The optional extras are skipped."
                    continue
                }
                throw "The $($g.AppName) Main folder is absent: $sourceMain`r`n    Verify the game files in Steam, then run this setup again."
            }

            Write-Step "Copy the $($g.AppName) data"
            $copied = 0; $current = 0; $skipped = 0

            foreach ($f in $entry.Files) {
                switch (Copy-GameFile -SourceDir $sourceMain -DestDir $mainDir -Name $f.Name) {
                    'copied'  { $copied++;  Write-Info ("copied   {0}" -f $f.Name) }
                    'current' { $current++ }
                    'missing' {
                        if ($f.Required) {
                            $missing += $f.Name
                            Write-Warn ("missing  {0}" -f $f.Name)
                        } else {
                            $skipped++
                            Write-Info ("skipped  {0} (optional, not installed)" -f $f.Name)
                        }
                    }
                }
            }

            Write-Info ("{0}: {1} copied, {2} already current, {3} optional skipped." -f $g.AppName, $copied, $current, $skipped)
        }

        if ($missing.Count -gt 0) {
            throw ("These required files were not found:`r`n    {0}`r`n`r`nVerify the game files in Steam, then run this setup again." -f ($missing -join "`r`n    "))
        }
    }

    # --- Verify --------------------------------------------------------------
    Write-Step "Verify the install"

    $absent = @()
    foreach ($f in $VrFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot $f))) { $absent += $f }
    }
    if ($absent.Count -gt 0) {
        throw ("The VR files did not unpack correctly. These are absent:`r`n    {0}" -f ($absent -join "`r`n    "))
    }

    foreach ($g in $FileGroups) {
        $gone = Get-AbsentFiles -Group $g -MainDir $mainDir
        if ($gone.Count -gt 0) {
            throw ("The $($g.AppName) data is incomplete. These are absent from $mainDir :`r`n    {0}" -f ($gone -join "`r`n    "))
        }
    }

    $totalMb = [math]::Round(((Get-ChildItem -LiteralPath $mainDir -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
    Write-Info "Main folder holds $totalMb MB."

    if ($CreateShortcut) {
        Write-Step "Make the desktop shortcut"
        New-DesktopShortcut -Root $InstallRoot
    }

    Write-Host ""
    Write-Host "Setup finished. Start RealRTCWXR.exe from $InstallRoot"
    exit $EXIT_OK
}
catch {
    Write-Host ""
    Write-Host "SETUP FAILED"
    Write-Host "------------"
    Write-Host $_.Exception.Message
    exit $EXIT_ERROR
}
