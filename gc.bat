@echo off
rem ===========================================================================
rem  gc - обёртка над "git checkout"
rem
rem  Использование:
rem    gc                       - git checkout (как обычно: покажет изменения)
rem    gc <ветка>               - git checkout <ветка>
rem    gc <ветка> <арг>         - git checkout <ветка> <арг> (start-point или путь)
rem    gc -                     - git checkout -  (предыдущая ветка)
rem    gc -b <ветка> [start]    - создать ветку и переключиться
rem    gc -B <ветка> [start]    - пересоздать ветку и переключиться
rem    gc -- <пути...>          - git checkout -- <пути...> (откат файлов)
rem    gc <ветка> -- <пути...>  - переключиться и откатить указанные файлы
rem    gc -h | --help           - эта справка
rem
rem  Опции git checkout пробрасываются как есть, в форме --opt или --opt=value
rem  (например: gc --detach HEAD~1, gc -f main, gc --track origin/dev).
rem  Опции, требующие отдельного значения (-b, -B, --orphan, --conflict,
rem  --pathspec-from-file), тоже поддерживаются: gc -b feature origin/main
rem ===========================================================================
setlocal EnableExtensions

set "OPTS="
set "BRANCH="
set "TAIL="
set "SEP="

rem ----------------------------- разбор аргументов ---------------------------
:parse
if "%~1"=="" goto check_git

rem всё, что после "--", - это пути
if defined SEP (
    set "TAIL=%TAIL% "%~1""
    shift
    goto parse
)

set "ARG=%~1"
if /i "%ARG%"=="-h"     goto help
if /i "%ARG%"=="/?"     goto help
if /i "%ARG%"=="--help" goto help
if "%ARG%"=="--" (
    set "SEP=1"
    set "TAIL=%TAIL% --"
    shift
    goto parse
)

rem опции, которым нужно отдельное значение: забираем следующий аргумент
if "%ARG%"=="-b" goto takes_value
if "%ARG%"=="-B" goto takes_value
if /i "%ARG%"=="--orphan" goto takes_value
if /i "%ARG%"=="--conflict" goto takes_value
if /i "%ARG%"=="--pathspec-from-file" goto takes_value

rem одиночный "-" - это предыдущая ветка, а не опция
if "%ARG%"=="-" goto positional

rem любые прочие опции (--detach, -f, --quiet, --opt=value, ...)
if "%ARG:~0,1%"=="-" (
    set "OPTS=%OPTS% %ARG%"
    shift
    goto parse
)

:positional
rem первый позиционный аргумент - цель checkout (ветка/коммит),
rem остальные - start point либо пути (передаём как есть, порядок сохраняем)
if not defined BRANCH (
    set "BRANCH=%ARG%"
) else (
    set "TAIL=%TAIL% "%ARG%""
)
shift
goto parse

rem ---------------------- опции со значением -------------------------------
:takes_value
if "%~2"=="" (
    echo gc: опция %ARG% требует значения>&2
    echo     например: gc %ARG% ИМЯ_ВЕТКИ>&2
    exit /b 2
)
set "OPTS=%OPTS% %ARG% "%~2""
shift
shift
goto parse

rem ------------------------------- проверки ---------------------------------
:check_git
git --version >nul 2>&1
if errorlevel 1 (
    echo gc: git не найден в PATH>&2
    exit /b 127
)

git rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
    echo gc: текущий каталог не является git-репозиторием: %CD%>&2
    exit /b 128
)

rem ------------------------------- выполнение --------------------------------
:run
set "CMD=git checkout%OPTS%"
if defined BRANCH set "CMD=%CMD% "%BRANCH%""
if defined TAIL   set "CMD=%CMD%%TAIL%"

echo ^> %CMD%
%CMD%
set "RC=%errorlevel%"
if "%RC%"=="0" exit /b 0

rem --------------------------- подсказка при ошибке --------------------------
echo gc: git checkout завершился с кодом %RC%.>&2
if not defined BRANCH goto end_err
if defined OPTS goto end_err

set "REMOTE="
for /f "delims=" %%r in ('git remote 2^>nul') do (
    if not defined REMOTE if /i "%%r"=="origin" set "REMOTE=origin"
)
if not defined REMOTE goto end_err

git rev-parse --verify --quiet "refs/remotes/%REMOTE%/%BRANCH%" >nul 2>&1
if errorlevel 1 goto end_err

echo     ветки "%BRANCH%" нет локально, но есть %REMOTE%/%BRANCH%.>&2
echo     создать и переключиться:  gc -b %BRANCH% %REMOTE%/%BRANCH%>&2

:end_err
exit /b %RC%

rem -------------------------------- справка ---------------------------------
:help
echo gc - краткая обёртка над "git checkout"
echo.
echo Использование:
echo   gc                        git checkout (покажет изменения)
echo   gc ^<ветка^>                git checkout ^<ветка^>
echo   gc ^<ветка^> ^<арг^>          git checkout ^<ветка^> ^<арг^> (start-point/путь)
echo   gc -                      git checkout -  (предыдущая ветка)
echo   gc -b ^<ветка^> [^<start^>]    создать ветку и переключиться
echo   gc -B ^<ветка^> [^<start^>]    пересоздать ветку и переключиться
echo   gc -- ^<пути...^>            откатить указанные файлы
echo   gc ^<ветка^> -- ^<пути...^>    переключиться и откатить файлы
echo   gc -h ^| --help            эта справка
echo.
echo Опции git checkout пробрасываются как есть:
echo   gc --detach HEAD~1
echo   gc -f main
echo   gc --quiet develop
echo   gc -b feature origin/main
echo   gc --track origin/dev
exit /b 0
