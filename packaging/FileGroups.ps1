# Game data that RealRTCW XR needs, grouped by the product it comes from.
# Make-Package.ps1 and Setup-RealRTCWXR.ps1 both read this. Keep it free of side effects.

$FileGroups = @(
    @{
        Key        = 'RTCW'
        AppId      = '9010'
        AppName    = 'Return to Castle Wolfenstein'
        SteamDir   = 'Return To Castle Wolfenstein'
        StoreUrl   = 'https://store.steampowered.com/app/9010/'
        SourceHint = 'the Main folder of your Return to Castle Wolfenstein installation'
        CheckBeta  = $false
        Files      = @(
            @{ Name = 'pak0.pk3';    Required = $true },
            @{ Name = 'sp_pak1.pk3'; Required = $true },
            @{ Name = 'sp_pak2.pk3'; Required = $true },
            @{ Name = 'sp_pak3.pk3'; Required = $true },
            @{ Name = 'sp_pak4.pk3'; Required = $true }
        )
    },
    @{
        Key        = 'RealRTCW'
        AppId      = '1379630'
        AppName    = 'RealRTCW'
        SteamDir   = 'RealRTCW'
        StoreUrl   = 'https://store.steampowered.com/app/1379630/RealRTCW/'
        SourceHint = 'the Main folder of your RealRTCW installation'
        CheckBeta  = $true
        Files      = @(
            @{ Name = 'realrtcwdefault.cfg';              Required = $true },
            @{ Name = 'autoexec.cfg';                     Required = $true },
            @{ Name = 'xbox.cfg';                         Required = $true },
            @{ Name = 'xbox_cinematic.cfg';               Required = $true },
            @{ Name = 'z_realrtcw_localization.pk3';      Required = $true },
            @{ Name = 'z_realrtcw_maps.pk3';              Required = $true },
            @{ Name = 'z_realrtcw_models.pk3';            Required = $true },
            @{ Name = 'z_realrtcw_models_characters.pk3'; Required = $true },
            @{ Name = 'z_realrtcw_models_weapons.pk3';    Required = $true },
            @{ Name = 'z_realrtcw_sounds.pk3';            Required = $true },
            @{ Name = 'z_realrtcw_textures.pk3';          Required = $true },
            @{ Name = 'z_zperson.pk3';                    Required = $true },
            @{ Name = 'z_zrealrtcw_ui.pk3';               Required = $true },
            @{ Name = 'z_zzrealrtcw_scripts.pk3';         Required = $true },
            @{ Name = 'z_zzzsurvival.pk3';                Required = $true },
            @{ Name = 'z_zrealrtcw_dlc1.pk3';             Required = $false },
            @{ Name = 'z_zzzrealrtcw_germanvoices.pk3';   Required = $false }
        )
    }
)
