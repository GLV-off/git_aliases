@echo off
rem ===========================================================================
rem  install.bat - установка git-алиасов (gc.bat, gp.bat) на этой машине
rem
rem  Что делает:
rem    1) создаёт постоянную пользовательскую переменную окружения, значение
rem       которой = каталог, в котором лежит этот скрипт;
rem    2) добавляет в пользовательский PATH ссылку на эту переменную
rem       (в PATH хранится %VAR% - путь остаётся рабочим при переносе папки);
rem    3) уведомляет Проводник Windows, чтобы новые окна терминала видели
rem       изменения без перезагрузки.
rem
rem  Использование:
rem    install.bat                  - установить, переменная GLV_GIT_ALIASES
rem    install.bat <VAR>            - установить с другим именем переменной
rem    install.bat <VAR> <каталог>  - ... и с явно заданным каталогом
rem
rem  Права администратора не нужны: пишем только в HKCU (текущий пользователь).
rem  Код возврата: 0 - успех, 1 - ошибка.
rem ===========================================================================

rem --- путь берём при выключенном delayed expansion, иначе "!" съедается ---
setlocal DisableDelayedExpansion
chcp 65001 >nul

set "VAR_NAME=%~1"
if "%VAR_NAME%"=="" set "VAR_NAME=GLV_GIT_ALIASES"
set "PATH_ENTRY=%%%VAR_NAME%%%"

set "TARGET_DIR=%~2"
if "%TARGET_DIR%"=="" set "TARGET_DIR=%~dp0"
if "%TARGET_DIR:~-1%"=="\" set "TARGET_DIR=%TARGET_DIR:~0,-1%"

set "KEY=HKCU\Environment"

echo.
echo === Установка git-алиасов ===
echo   переменная окружения : %VAR_NAME%
echo   значение             : %TARGET_DIR%
echo   элемент PATH         : %PATH_ENTRY%
echo.

rem ------------------------------- проверки --------------------------------
if not exist "%TARGET_DIR%\" (
    echo [ОШИБКА] каталог не найден: %TARGET_DIR%
    exit /b 1
)

set "NO_BANG=%TARGET_DIR:!=%"
if not "%NO_BANG%"=="%TARGET_DIR%" (
    echo [ОШИБКА] в пути есть символ "!" - с ним установка не работает.
    echo         Скопируйте скрипты в каталог без "!" и запустите оттуда.
    exit /b 1
)

if "%TARGET_DIR:~0,2%"=="\\" (
    echo [ВНИМАНИЕ] каталог задан UNC-путём: %TARGET_DIR%
    echo            UNC-пути в PATH работают нестабильно, а cmd.exe не умеет
    echo            использовать UNC как текущий каталог. Лучше локальный диск.
    echo.
)

reg query "%KEY%" >nul 2>&1
if errorlevel 1 (
    echo [ОШИБКА] не удалось прочитать раздел реестра %KEY%
    exit /b 1
)

setlocal EnableDelayedExpansion

rem ------------------- 1. пользовательская переменная ----------------------
reg add "%KEY%" /v "%VAR_NAME%" /t REG_SZ /d "%TARGET_DIR%" /f >nul
if errorlevel 1 (
    echo [ОШИБКА] не удалось записать переменную %VAR_NAME% в реестр.
    exit /b 1
)
echo [1/3] переменная %VAR_NAME% = %TARGET_DIR% создана.

rem ------------------------ 2. пользовательский PATH -----------------------
set "USER_PATH="
for /f "usebackq tokens=2,*" %%A in (`reg query "%KEY%" /v Path 2^>nul`) do set "USER_PATH=%%B"

if not "!USER_PATH!"=="%USER_PATH%" (
    echo [ОШИБКА] в текущем PATH есть символ "!" - автообновление невозможно.
    echo         Добавьте в PATH вручную элемент: %PATH_ENTRY%
    exit /b 1
)

rem уже есть? ищем %VAR% или развёрнутый путь; "\;" приводим к ";" для сравнения
set "PADDED=;!USER_PATH!;"
set "PADDED=!PADDED:\;=;!"
set "PRESENT="
if /i not "!PADDED:;%PATH_ENTRY%;=!"=="!PADDED!" set "PRESENT=1"
if /i not "!PADDED:;%TARGET_DIR%;=!"=="!PADDED!" set "PRESENT=1"

if defined PRESENT (
    echo [2/3] PATH уже содержит %PATH_ENTRY% - оставляем как есть.
) else (
    set "NEW_PATH=%PATH_ENTRY%"
    if defined USER_PATH (
        if "!USER_PATH:~-1!"==";" set "USER_PATH=!USER_PATH:~0,-1!"
        set "NEW_PATH=!USER_PATH!;%PATH_ENTRY%"
    )
    reg add "%KEY%" /v Path /t REG_EXPAND_SZ /d "!NEW_PATH!" /f >nul
    if errorlevel 1 (
        echo [ОШИБКА] не удалось записать PATH в реестр.
        exit /b 1
    )
    echo [2/3] в PATH добавлен элемент %PATH_ENTRY%.
)

rem ------------- 3. уведомляем систему об изменении окружения --------------
where setx >nul 2>&1
if errorlevel 1 (
    echo [3/3] setx не найден - изменения подхватятся после входа в систему.
    goto :done
)

rem setx нужен не для записи значения, а ради широковещательного сообщения
rem WM_SETTINGCHANGE, по которому Проводник перечитывает окружение.
setx "%VAR_NAME%" "%TARGET_DIR%" >nul 2>&1

rem setx молча обрезает значения длиннее 1024 символов - проверяем и правим
set "CHK="
for /f "usebackq tokens=2,*" %%A in (`reg query "%KEY%" /v "%VAR_NAME%" 2^>nul`) do set "CHK=%%B"
if not "%CHK%"=="%TARGET_DIR%" (
    reg add "%KEY%" /v "%VAR_NAME%" /t REG_SZ /d "%TARGET_DIR%" /f >nul
    echo [3/3] ВНИМАНИЕ: setx исказил значение, записано напрямую в реестр.
    echo       Чтобы окружение обновилось, перезайдите в систему.
    goto :done
)
echo [3/3] Проводник Windows уведомлён об изменении окружения.

:done
echo.
echo Установка завершена: %TARGET_DIR%
echo Откройте НОВОЕ окно терминала и проверьте:
echo     echo %PATH_ENTRY%
echo     where gc
echo     gc -h
echo.
exit /b 0
