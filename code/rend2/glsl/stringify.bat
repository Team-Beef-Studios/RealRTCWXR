for %%f in (*.glsl) do (
	"..\..\..\code\RealRTCWXR\x64\Debug\stringify.exe" "%%f" "%%~nf.c"
)