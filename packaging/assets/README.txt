Binary assets that the installer ships but that no build step produces.

    z_realrtcw_models_hands_vr.pk3          VR hand models (models/weapons/vrhands)
    z_zzzz_remastered_digitaldeluxe_3.pk3   VR modified weapon models and textures

Both files are too large for GitHub, so .gitignore excludes packaging/assets/*.pk3.
Keep them here anyway. Make-Package.ps1 reads this folder first.

If a file is absent here, the build falls back to the copy in
code\RealRTCWXR\x64\<Config>\Main and prints a warning.
