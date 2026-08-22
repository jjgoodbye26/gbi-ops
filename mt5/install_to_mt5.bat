@echo off
rem ============================================================
rem  NDR Dashboard installer for MetaTrader 5 (Windows)
rem  Put this file in the SAME folder as NDR_Dashboard2.mq5
rem  then double-click it.
rem ============================================================
setlocal enabledelayedexpansion

set "SRC=%~dp0NDR_Dashboard2.mq5"
if not exist "%SRC%" (
    echo.
    echo ERROR: NDR_Dashboard2.mq5 was not found in this folder:
    echo   %~dp0
    echo Put this script in the same folder as NDR_Dashboard2.mq5 and run it again.
    echo.
    pause
    exit /b 1
)

set FOUND=0
for /d %%D in ("%APPDATA%\MetaQuotes\Terminal\*") do (
    if exist "%%D\MQL5\Indicators" (
        copy /y "%SRC%" "%%D\MQL5\Indicators\" >nul
        echo Installed into: %%D\MQL5\Indicators
        set /a FOUND+=1
    )
)

echo.
if %FOUND%==0 (
    echo No MetaTrader 5 data folders were found under:
    echo   %APPDATA%\MetaQuotes\Terminal
    echo.
    echo Your MT5 may be installed in "portable mode". In that case, open MT5,
    echo go to File - Open Data Folder, then copy NDR_Dashboard2.mq5 into
    echo MQL5\Indicators yourself.
) else (
    echo Done! Copied to %FOUND% MT5 installation^(s^).
    echo.
    echo NEXT STEPS in MetaTrader 5:
    echo  1. Restart MT5 ^(or press F4, open the file, press F7 to compile^).
    echo  2. Ctrl+N - Indicators - Custom - drag NDR_Dashboard2 onto your chart.
    echo  3. Enter your Telegram bot token + chat ID in the inputs.
    echo  4. Right-click chart - Templates - Save Template - name it "Default".
)
echo.
pause
