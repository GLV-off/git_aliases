@echo off
rem ===========================================================================
rem  gp - обёртка над "git pull"
rem
rem  Использование:
rem    gp                       - git pull (как обычно; если upstream не задан,
rem                               тянет текущую ветку из origin)
rem    gp <ветка>               - git pull origin <ветка>
rem    gp <remote> <ветка>      - git pull <remote> <ветка>
rem    gp --rebase [ветка]      - опции git pull пробрасываются как есть
rem    gp -h | --help           - эта справка
rem
rem  Опции git pull передавайте в форме --opt или --opt=value
rem  (например: gp --ff-only, gp --rebase --autostash main).
rem ===========================================================================
setlocal EnableExtensions

set "REMOTE="
set "BRANCH="
set "OPTS="

rem ----------------------------- разбор аргументов ---------------------------
:parse
if "%~1"=="" goto check_git
if /i "%~1"=="-h"     goto help
if /i "%~1"=="/?"     goto help
if /i "%~1"=="--help" goto help

set "ARG=%~1"
if "%ARG:~0,1%"=="-" (
    set "OPTS=%OPTS% %~1"
) else (
    if not defined REMOTE (
        set "REMOTE=%~1"
    ) else if not defined BRANCH (
        set "BRANCH=%~1"
    ) else (
        echo gp: слишком много аргументов: %~1>&2
        echo     подсказка: gp [опции] [remote] [ветка]>&2
        exit /b 2
    )
)
shift
goto parse

rem ------------------------------- проверки ---------------------------------
:check_git
git --version >nul 2>&1
if errorlevel 1 (
    echo gp: git не найден в PATH>&2
    exit /b 127
)

git rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
    echo gp: текущий каталог не является git-репозиторием: %CD%>&2
    exit /b 128
)

rem ------------------- удалённый репозиторий по умолчанию -------------------
rem origin, если он есть, иначе первый из списка
set "DEFREMOTE="
for /f "delims=" %%r in ('git remote 2^>nul') do (
    if not defined DEFREMOTE set "DEFREMOTE=%%r"
    if /i "%%r"=="origin" set "DEFREMOTE=origin"
)
if not defined DEFREMOTE set "DEFREMOTE=origin"

rem --------------------------- текущая ветка / upstream ----------------------
set "CURBRANCH="
for /f "delims=" %%b in ('git symbolic-ref --quiet --short HEAD 2^>nul') do set "CURBRANCH=%%b"

set "UPSTREAM="
for /f "delims=" %%u in ('git rev-parse --abbrev-ref --symbolic-full-name @{u} 2^>nul') do set "UPSTREAM=%%u"

rem ------------------------- выбор цели для git pull -------------------------
if defined REMOTE goto normalize

rem позиционных аргументов нет
if defined UPSTREAM goto run          rem всё настроено - обычный git pull
if not defined CURBRANCH goto detached
rem upstream не настроен - тянем текущую ветку из удалённого по умолчанию
set "REMOTE=%DEFREMOTE%"
set "BRANCH=%CURBRANCH%"
goto run

:detached
echo gp: HEAD отсоединён (detached HEAD) - непонятно, что тянуть.>&2
echo     укажите ветку явно: gp ^<ветка^>  или  gp ^<remote^> ^<ветка^>>&2
exit /b 1

:normalize
rem один позиционный аргумент трактуем как ветку на удалённом по умолчанию
if not defined BRANCH (
    set "BRANCH=%REMOTE%"
    set "REMOTE=%DEFREMOTE%"
)

rem ------------------------------- выполнение --------------------------------
:run
set "CMD=git pull%OPTS%"
if defined REMOTE set "CMD=%CMD% %REMOTE%"
if defined BRANCH set "CMD=%CMD% %BRANCH%"

echo ^> %CMD%
%CMD%
exit /b %errorlevel%

rem -------------------------------- справка ---------------------------------
:help
echo gp - краткая обёртка над "git pull"
echo.
echo Использование:
echo   gp                      git pull (если upstream не настроен -
echo                           git pull ^<remote по умолчанию^> ^<текущая ветка^>)
echo   gp ^<ветка^>              git pull ^<remote по умолчанию^> ^<ветка^>
echo   gp ^<remote^> ^<ветка^>     git pull ^<remote^> ^<ветка^>
echo   gp -h ^| --help          эта справка
echo.
echo Опции git pull пробрасываются как есть, в форме --opt или --opt=value:
echo   gp --rebase
echo   gp --ff-only main
echo   gp --rebase --autostash origin develop
exit /b 0
