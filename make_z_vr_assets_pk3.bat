cd z_zzRealRTCWXR
del z_zzRealRTCWXR.pk3
cd ..
powershell Compress-Archive z_zzRealRTCWXR/* z_zzRealRTCWXR.zip
rename z_zzRealRTCWXR.zip z_zzRealRTCWXR.pk3
copy z_zzRealRTCWXR.pk3 code\RealRTCWXR\x64\Debug\Main\*.*
move z_zzRealRTCWXR.pk3 code/RealRTCWXR/x64/Release/Main

pause
