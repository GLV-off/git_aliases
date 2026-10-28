@echo off
rem ===========================================================================
rem  gcb - обёртка над "git checkout -b": создать ветку и переключиться на неё
rem
rem  Использование:
rem    gcb <ветка>               - git checkout -b <ветка> HEAD
rem    gcb <ветка> <start>       - git checkout -b <ветка> <start>
rem    gcb <ветка> --from <start> - то же самое, но start задан явно
rem    gcb -B <ветка> [start]    - пересоздать (сбросить) ветку
rem    gcb -o <ветка>            - пустая (orphan) ветка без истории
rem    gcb -h | --help           - эта справка
rem
rem  Если start не указан, а на удалённом репозитории (origin) уже есть ветка
rem  с таким именем, стартуем от неё и настраиваем upstream (как это делает
rem  "git checkout <ветка>"). Отключить: gcb --no-track <ветка>.
rem
rem  Опции git checkout пробрасываются как есть, в форме --opt или --opt=value:
rem    gcb -t feature origin/dev      (--track)
rem    gcb --no-track feature         (не связывать с upstream)
rem    gcb --quiet feature
rem ===========================================================================
setlocal EnableExtensions

set "OPTS="
set "BRANCH="
set "START="
set "RESET="
set "ORPHAN="

rem ----------------------------- разбор аргументов ---------------------------
:parse
if "%~1"=="" goto validate

set "ARG=%~1"
if /i "%ARG%"=="-h"     goto help
if /i "%ARG%"=="/?"     goto help
if /i "%ARG%"=="--help" goto help

rem "-b" не нужен: скрипт сам добавляет его к команде
if "%ARG%"=="-b" (
    shift
    goto parse
)
if "%ARG%"=="-B"         goto flag_reset
if "%ARG%"=="-o"         goto flag_orphan
if /i "%ARG%"=="--orphan" goto flag_orphan
if /i "%ARG%"=="--from"  goto takes_from

rem --from=<ref>
if /i "%ARG:~0,7%"=="--from=" (
    set "START=%ARG:~7%"
    shift
    goto parse
)

rem любые прочие опции git checkout (--track, --no-track, --quiet, -f, ...)
if "%ARG:~0,1%"=="-" (
    set "OPTS=%OPTS% %ARG%"
    shift
    goto parse
)

rem позиционные аргументы: сначала имя ветки, затем start point
if not defined BRANCH (
    set "BRANCH=%ARG%"
) else if not defined START (
    set "START=%ARG%"
) else (
    echo gcb: слишком много аргументов: %ARG%>&2
    echo     подсказка: gcb [опции] ^<ветка^> [start]>&2
    exit /b 2
)
shift
goto parse

:flag_reset
set "RESET=1"
shift
goto parse

:flag_orphan
set "ORPHAN=1"
shift
goto parse

:takes_from
if "%~2"=="" (
    echo gcb: --from требует значения: ^<ветка/тег/коммит^>.>&2
    exit /b 2
)
set "START=%~2"
shift
shift
goto parse

rem -------------------------- проверка аргументов ---------------------------
:validate
git --version >nul 2>&1
if errorlevel 1 (
    echo gcb: git не найден в PATH>&2
    exit /b 127
)

git rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
    echo gcb: текущий каталог не является git-репозиторием: %CD%>&2
    exit /b 128
)

if not defined BRANCH (
    echo gcb: не указано имя ветки>&2
    echo     подсказка: gcb ^<ветка^> [start]   справка: gcb -h>&2
    exit /b 2
)

git check-ref-format --branch "%BRANCH%" >nul 2>&1
if errorlevel 1 (
    echo gcb: недопустимое имя ветки: "%BRANCH%">&2
    echo     нельзя: пробелы, .., ~, ^^, :, ?, *, [, \, @{, а также имена,>&2
    echo     начинающиеся с "-" или заканчивающиеся на "/" или ".lock">&2
    exit /b 2
)

rem ------------------------- уже существует? --------------------------------
if defined ORPHAN goto check_start

git rev-parse --verify --quiet "refs/heads/%BRANCH%" >nul 2>&1
if errorlevel 1 goto check_start
if defined RESET goto check_start

echo gcb: ветка "%BRANCH%" уже существует - ничего не делаю.>&2
echo     переключиться на неё:    gc %BRANCH%>&2
echo     пересоздать от старта:   gcb -B %BRANCH% [start]>&2
exit /b 1

rem --------------------------- start point ----------------------------------
:check_start
if defined ORPHAN goto run
if defined START goto verify_start

rem start не задан: ищем одноимённую ветку на удалённом репозитории
set "DEFREMOTE="
for /f "delims=" %%r in ('git remote 2^>nul') do (
    if not defined DEFREMOTE set "DEFREMOTE=%%r"
    if /i "%%r"=="origin" set "DEFREMOTE=origin"
)

if defined DEFREMOTE (
    git rev-parse --verify --quiet "refs/remotes/%DEFREMOTE%/%BRANCH%" >nul 2>&1
    if not errorlevel 1 (
        set "START=%DEFREMOTE%/%BRANCH%"
        echo gcb: локальной ветки "%BRANCH%" нет, но есть %DEFREMOTE%/%BRANCH% - стартуем от неё>&2
        goto verify_start
    )
)

set "START=HEAD"
goto verify_start

:verify_start
git rev-parse --verify --quiet "%START%^{commit}" >nul 2>&1
if errorlevel 1 (
    echo gcb: не найдена начальная точка: "%START%">&2
    echo     это должна быть ветка, тег или коммит. Посмотреть варианты:>&2
    echo       git branch -a    ^(ветки^)      git tag    ^(теги^)>&2
    exit /b 129
)

rem ------------------------------- выполнение --------------------------------
:run
if defined ORPHAN goto run_orphan

set "CMD=git checkout%OPTS%"
if defined RESET (
    set "CMD=%CMD% -B"
) else (
    set "CMD=%CMD% -b"
)
set "CMD=%CMD% "%BRANCH%" "%START%""
goto exec

:run_orphan
set "CMD=git checkout%OPTS% --orphan "%BRANCH%""

:exec
echo ^> %CMD%
%CMD%
set "RC=%errorlevel%"
if not "%RC%"=="0" (
    echo gcb: git checkout завершился с кодом %RC%.>&2
    exit /b %RC%
)

rem -------------------- подсказка про публикацию ветки ----------------------
if defined ORPHAN exit /b 0
git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >nul 2>&1
if not errorlevel 1 exit /b 0

set "PUSHREMOTE="
for /f "delims=" %%r in ('git remote 2^>nul') do (
    if not defined PUSHREMOTE set "PUSHREMOTE=%%r"
    if /i "%%r"=="origin" set "PUSHREMOTE=origin"
)
if not defined PUSHREMOTE set "PUSHREMOTE=origin"

echo gcb: upstream не задан - опубликовать ветку:  git push -u %PUSHREMOTE% %BRANCH%
exit /b 0

rem -------------------------------- справка ---------------------------------
:help
echo gcb - создать ветку и переключиться на неё (git checkout -b)
echo.
echo Использование:
echo   gcb ^<ветка^>                 git checkout -b ^<ветка^> HEAD
echo   gcb ^<ветка^> ^<start^>         git checkout -b ^<ветка^> ^<start^>
echo   gcb ^<ветка^> --from ^<start^>   то же самое, start задан явно
echo   gcb -B ^<ветка^> [start]       пересоздать (сбросить) ветку
echo   gcb -o ^<ветка^>               пустая (orphan) ветка без истории
echo   gcb -h ^| --help              эта справка
echo.
echo Если start не указан и на origin есть одноимённая ветка, стартуем от неё
echo (upstream настроится автоматически). Отключить: --no-track.
echo.
echo Примеры:
echo   gcb feature/login
echo   gcb bugfix/42 v1.2.3
echo   gcb review origin/dev
echo   gcb --no-track scratch
echo   gcb -B nightly main
echo   gcb -o docs
exit /b 0
