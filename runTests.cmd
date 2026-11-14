@echo off
rem Runs the test suite (tests\run_tests.py). Double-click it, or run it from a command prompt or
rem PowerShell in any folder; any arguments go to run_tests.py:
rem     runTests                  every test
rem     runTests flight pins      some of them
rem     runTests --update flight  accept a test's new output (only once you've checked the diff)
rem Needs Python 3 with lupa and pillow (pip install lupa pillow). Like localDeploy.cmd, it
rem pauses only if something failed, so a double-clicked window stays open to read why.
setlocal
set "PY="
rem The python.exe in WindowsApps is only a Microsoft Store stub, so look for a real one.
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do if exist "%%D\python.exe" set "PY=%%D\python.exe"
if defined PY goto run
where py >nul 2>nul
if not errorlevel 1 (
    py -3 "%~dp0tests\run_tests.py" %*
    goto done
)
echo No Python 3 found. Install it, then: pip install lupa pillow
pause
exit /b 1

:run
"%PY%" "%~dp0tests\run_tests.py" %*

:done
if errorlevel 1 pause
