@echo off
rem Collect logs from a Redmi Pad Pro (dizi) / Redmi Pad Pro 5G, POCO Pad 5G (ruan) running this
rem Evolution X build, into one zip to send to the maintainer.
rem
rem Needs adb (Android platform-tools): put adb.exe, AdbWinApi.dll and AdbWinUsbApi.dll next to
rem this file, or adb on PATH. Turn on USB debugging (Settings > System > Developer options), or
rem boot the tablet to recovery. Reproduce the problem first, then run this right away: the logs
rem only reach back a few minutes.
rem
rem The logs can contain your phone number, IMEI, SIM and network details, and Wi-Fi names.
rem Only send the zip to the maintainer.
setlocal enableextensions

set "ADB=adb"
if exist "%~dp0adb.exe" set "ADB=%~dp0adb.exe"
"%ADB%" version >nul 2>&1
if errorlevel 1 (
    echo adb not found. Put adb.exe from Android platform-tools next to this file or on PATH.
    pause
    exit /b 1
)

set "TMPF=%TEMP%\collect-logs-%RANDOM%.txt"
set "STATE="
"%ADB%" get-state > "%TMPF%" 2>nul
set /p STATE=<"%TMPF%"
if not "%STATE%"=="device" if not "%STATE%"=="recovery" (
    echo Waiting for the tablet ^(plug it in and allow USB debugging on its screen^)...
    "%ADB%" wait-for-any-device
    "%ADB%" get-state > "%TMPF%" 2>nul
    set /p STATE=<"%TMPF%"
)

set "DEVICE=tablet"
"%ADB%" shell getprop ro.product.device > "%TMPF%" 2>nul
set /p DEVICE=<"%TMPF%"
del "%TMPF%" >nul 2>&1
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%t"
set "OUT=%CD%\logs-%DEVICE%-%TS%"
mkdir "%OUT%"
echo Collecting from %DEVICE% (%STATE%) into %OUT% ...

rem Root (bench builds only) gives dmesg, pstore and tombstones directly; otherwise the bug
rem report below has them.
"%ADB%" root >nul 2>&1
timeout /t 3 /nobreak >nul
"%ADB%" wait-for-any-device

if "%STATE%"=="recovery" (
    "%ADB%" shell cat /tmp/recovery.log > "%OUT%\recovery.log" 2>&1
    "%ADB%" shell dmesg > "%OUT%\dmesg.txt" 2>&1
    goto pstore
)

"%ADB%" shell getprop > "%OUT%\getprop.txt" 2>&1
"%ADB%" logcat -b all -d > "%OUT%\logcat.txt" 2>&1
"%ADB%" logcat -b radio -d > "%OUT%\logcat-radio.txt" 2>&1
"%ADB%" logcat -b crash -d > "%OUT%\logcat-crash.txt" 2>&1
"%ADB%" shell dmesg > "%OUT%\dmesg.txt" 2>&1
"%ADB%" shell "getprop | grep init.svc" > "%OUT%\services.txt" 2>&1
"%ADB%" shell lshal -itp > "%OUT%\lshal.txt" 2>&1
"%ADB%" shell service list > "%OUT%\service-list.txt" 2>&1
"%ADB%" shell lsmod > "%OUT%\lsmod.txt" 2>&1
"%ADB%" shell getenforce > "%OUT%\selinux.txt" 2>&1
for %%d in (telephony.registry isub carrier_config phone connectivity wifi location battery) do (
    "%ADB%" shell dumpsys %%d > "%OUT%\dumpsys-%%d.txt" 2>&1
)
"%ADB%" shell dumpsys activity service com.android.phone > "%OUT%\dumpsys-phone-service.txt" 2>&1
"%ADB%" shell "ls -l /data/tombstones /data/anr" > "%OUT%\tombstones-list.txt" 2>&1
"%ADB%" pull /data/tombstones "%OUT%\tombstones" >nul 2>&1
"%ADB%" pull /data/anr "%OUT%\anr" >nul 2>&1
rem Works without root: dumpstate adds the kernel log, tombstones, ANRs and radio state.
echo Taking a bug report (1-3 minutes)...
"%ADB%" bugreport "%OUT%\bugreport.zip" >nul 2>&1

:pstore
rem Kernel log of the previous boot (after a crash or a reboot loop).
"%ADB%" pull /sys/fs/pstore "%OUT%\pstore" >nul 2>&1

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%' -DestinationPath '%OUT%.zip' -Force"
echo.
echo Done: %OUT%.zip
echo Send this file, with a short description of what went wrong and when.
pause
