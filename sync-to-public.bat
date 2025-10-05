@echo off
echo Syncing C:\ClaudeRepo to C:\Users\Public\ClaudeRepo...
echo.

REM Mirror C:\ClaudeRepo to Public folder, excluding git and node_modules
robocopy "C:\ClaudeRepo" "C:\Users\Public\ClaudeRepo" /MIR /XD ".git" "node_modules" /XF "sync-to-public.bat" /FFT /Z /W:5

echo.
echo Sync complete!
echo.
pause
