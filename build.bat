@echo off
rem led - build everything on Windows.
setlocal
set DIR=%~dp0
echo ==^> app
lazbuild --widgetset=win32 "%DIR%app\led.lpi" || exit /b 1
echo ==^> core tests
lazbuild --widgetset=nogui "%DIR%test\ledcoretest.lpi" || exit /b 1
echo.
echo built: %DIR%bin\led.exe
