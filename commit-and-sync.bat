@echo off
REM Commit, Sync, and Push - All-in-one script

echo ========================================
echo Step 1: Adding changes to git...
echo ========================================
git add .

echo.
echo ========================================
echo Step 2: Committing changes...
echo ========================================
set /p commit_msg="Enter commit message: "
git commit -m "%commit_msg%"

if errorlevel 1 (
    echo.
    echo No changes to commit.
    pause
    exit /b
)

echo.
echo ========================================
echo Step 3: Syncing to Public folder...
echo ========================================
call sync-to-public.bat

echo.
echo ========================================
echo Step 4: Pushing to GitHub...
echo ========================================
git push

echo.
echo ========================================
echo All done! Changes committed, synced, and pushed.
echo ========================================
pause
