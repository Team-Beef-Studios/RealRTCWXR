cd z_zzRealRTCWXR
del z_zzzRealRTCWXR.pk3
cd ..
powershell Compress-Archive z_zzRealRTCWXR/* z_zzzRealRTCWXR.zip
rename z_zzzRealRTCWXR.zip z_zzzRealRTCWXR.pk3
copy z_zzzRealRTCWXR.pk3 code\RealRTCWXR\x64\Debug\Main\*.*
move z_zzzRealRTCWXR.pk3 code/RealRTCWXR/x64/Release/Main

pause
