@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "MODE=standard"
set "ARGS="

:parse
if "%~1"=="" goto run
if "%~1"=="quick" set "MODE=quick" & shift & goto parse
if "%~1"=="standard" set "MODE=standard" & shift & goto parse
if "%~1"=="deep" set "MODE=deep" & shift & goto parse
if "%~1"=="beast" set "MODE=beast" & shift & goto parse
if "%~1"=="--continue" (
    set "ARGS=%ARGS% --continue"
) else (
    set "ARGS=%ARGS% %1"
)
shift
goto parse

:run
echo Launching VeerSkills (%MODE% mode)...
claude -p "%SCRIPT_DIR%\SKILL.md" "Follow the VeerSkills pipeline perfectly. Run a %MODE% audit on: %ARGS%"
