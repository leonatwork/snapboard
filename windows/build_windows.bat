@echo off
echo Building Snapboard for Windows (x64)...
dotnet publish Snapboard.Windows\Snapboard.Windows.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o bin\Release\win-x64
echo.
echo Build finished! Executable is located at: bin\Release\win-x64\Snapboard.exe
pause
