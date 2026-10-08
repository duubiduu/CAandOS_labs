@echo off
setlocal
chcp 65001 >nul

fltmc >nul 2>nul
if errorlevel 1 (
    echo Запустите script2.bat от имени администратора.
    exit /b 1
)
set "MAIN_SCRIPT=%~dp0script1.bat"
set "DRIVE_LETTER="
for %%L in (Z Y X W V U T S R Q P O N M L K J I H G F E D) do (
    if not defined DRIVE_LETTER (
        if not exist "%%L:\" (
            set "DRIVE_LETTER=%%L"
        )
    )
)
if not defined DRIVE_LETTER exit /b 1
set "TEST_DIR=%TEMP%\lab1_%RANDOM%_%RANDOM%"
if exist "%TEST_DIR%" exit /b 1
mkdir "%TEST_DIR%"
if errorlevel 1 exit /b 1
set "VHD_PATH=%TEST_DIR%\test.vhd"
set "LOG_DIR=%DRIVE_LETTER%:\log"

(
    echo create vdisk file="%VHD_PATH%" maximum=800 type=expandable
    echo attach vdisk
    echo create partition primary
    echo format fs=ntfs quick label=LAB1_TEST
    echo assign letter=%DRIVE_LETTER%
    echo exit
) > "%TEST_DIR%\setup.txt"
diskpart.exe /s "%TEST_DIR%\setup.txt" > "%TEST_DIR%\diskpart.log" 2>&1
if errorlevel 1 (
    type "%TEST_DIR%\diskpart.log"
    goto failed
)

call :test 1 70 1 gzip
if errorlevel 1 goto failed
call :test 2 90 0 none
if errorlevel 1 goto failed
call :test 3 50 3 oldest
if errorlevel 1 goto failed
call :test 4 75 0 boundary
if errorlevel 1 goto failed
call :test 5 70 1 lzma
if errorlevel 1 goto failed
call :cleanup
if errorlevel 1 exit /b 1
echo Все 5 тестов пройдены. Тестовый диск удалён.
exit /b 0

:failed
echo [FAIL] Тест не пройден.
if exist "%TEST_DIR%\run.log" type "%TEST_DIR%\run.log"
call :cleanup
exit /b 1

:test
set "NUMBER=%1"
set "X_LIMIT=%2"
set "EXPECTED_COUNT=%3"
set "MODE=%4"
set "BACKUP_DIR=%TEST_DIR%\backup_%NUMBER%"
set "RESTORE_DIR=%TEST_DIR%\restore_%NUMBER%"
set "LAB1_MAX_COMPRESSION="
if "%MODE%"=="lzma" set "LAB1_MAX_COMPRESSION=1"
echo Тест %NUMBER%: %MODE%, 600 МиБ логов.
call :generate_files
if errorlevel 1 exit /b 1
if "%MODE%"=="boundary" (
    powershell.exe -NoProfile -Command ^
        "$ErrorActionPreference = 'Stop';" ^
        "$disk = [IO.DriveInfo]::new($env:DRIVE_LETTER + ':\');" ^
        "$total = $disk.TotalSize;" ^
        "$used = $total - $disk.TotalFreeSpace;" ^
        "[math]::Ceiling(100 * $used / $total)" > "%TEST_DIR%\threshold.txt"
    if errorlevel 1 exit /b 1
    set /p X_LIMIT=<"%TEST_DIR%\threshold.txt"
)
call "%MAIN_SCRIPT%" "%LOG_DIR%" "%X_LIMIT%" "%BACKUP_DIR%" > "%TEST_DIR%\run.log" 2>&1
if errorlevel 1 exit /b 1
call :check_result
if errorlevel 1 exit /b 1
echo [OK] Тест %NUMBER%.
exit /b 0

:generate_files
powershell.exe -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$parts = Get-DiskImage -ImagePath $env:VHD_PATH | Get-Disk | Get-Partition;" ^
    "if ($parts.DriveLetter -notcontains $env:DRIVE_LETTER) {" ^
    "    throw 'Тестовый диск не подключён';" ^
    "};" ^
    "$log = $env:DRIVE_LETTER + ':\log';" ^
    "if (Test-Path -LiteralPath $log) {" ^
    "    Remove-Item -LiteralPath $log -Recurse -Force;" ^
    "};" ^
    "New-Item -ItemType Directory -Path $log, $env:BACKUP_DIR, $env:RESTORE_DIR > $null;" ^
    "for ($i = 1; $i -le 6; $i++) {" ^
    "    $path = Join-Path $log ('file_' + $i + '.log');" ^
    "    fsutil.exe file createnew $path 104857600 > $null;" ^
    "    if ($LASTEXITCODE -ne 0) {" ^
    "        throw 'Не удалось создать тестовый файл';" ^
    "    };" ^
    "    (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date '2024-01-30').AddDays(-$i);" ^
    "};" ^
    "$files = Get-ChildItem -LiteralPath $log;" ^
    "$size = ($files | Measure-Object Length -Sum).Sum;" ^
    "if ($size -lt 512MB) {" ^
    "    throw 'Размер логов меньше 0,5 ГиБ';" ^
    "};"
exit /b %ERRORLEVEL%

:check_result
powershell.exe -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$count = [int]$env:EXPECTED_COUNT;" ^
    "$archives = @(Get-ChildItem -LiteralPath $env:BACKUP_DIR -File);" ^
    "if ($count -eq 0) {" ^
    "    if ($archives.Count -ne 0) {" ^
    "        throw 'Архив не должен создаваться';" ^
    "    };" ^
    "} else {" ^
    "    if ($archives.Count -ne 1) {" ^
    "        throw 'Ожидался один архив';" ^
    "    };" ^
    "    $extension = '.gz';" ^
    "    if ($env:MODE -eq 'lzma') {" ^
    "        $extension = '.lzma';" ^
    "    };" ^
    "    if ($archives[0].Extension -ne $extension) {" ^
    "        throw 'Неверный формат архива';" ^
    "    };" ^
    "    tar.exe -xf $archives[0].FullName -C $env:RESTORE_DIR;" ^
    "    if ($LASTEXITCODE -ne 0) {" ^
    "        throw 'Не удалось распаковать архив';" ^
    "    };" ^
    "};" ^
    "for ($i = 1; $i -le 6; $i++) {" ^
    "    $name = 'file_' + $i + '.log';" ^
    "    $source = Join-Path $env:LOG_DIR $name;" ^
    "    $restored = Join-Path $env:RESTORE_DIR $name;" ^
    "    if ($i -gt 6 - $count) {" ^
    "        if (Test-Path -LiteralPath $source) {" ^
    "            throw ('Не удалён старый файл: ' + $name);" ^
    "        };" ^
    "        if ((Get-Item -LiteralPath $restored).Length -ne 100MB) {" ^
    "            throw 'Неверный размер файла в архиве';" ^
    "        };" ^
    "    } else {" ^
    "        if ((Get-Item -LiteralPath $source).Length -ne 100MB) {" ^
    "            throw 'Изменился оставшийся файл';" ^
    "        };" ^
    "        if (Test-Path -LiteralPath $restored) {" ^
    "            throw ('Лишний файл в архиве: ' + $name);" ^
    "        };" ^
    "    };" ^
    "};" ^
    "$restoredFiles = @(Get-ChildItem -LiteralPath $env:RESTORE_DIR -File);" ^
    "if ($restoredFiles.Count -ne $count) {" ^
    "    throw 'Неверное число файлов в архиве';" ^
    "};" ^
    "$disk = [IO.DriveInfo]::new($env:DRIVE_LETTER + ':\');" ^
    "$percent = [math]::Ceiling(100 * ($disk.TotalSize - $disk.TotalFreeSpace) / $disk.TotalSize);" ^
    "if ($percent -gt [int]$env:X_LIMIT) {" ^
    "    throw 'Порог не достигнут';" ^
    "};"
exit /b %ERRORLEVEL%

:cleanup
powershell.exe -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "if (Test-Path -LiteralPath $env:VHD_PATH) {" ^
    "    Dismount-DiskImage -ImagePath $env:VHD_PATH > $null;" ^
    "    if ((Get-DiskImage -ImagePath $env:VHD_PATH).Attached) {" ^
    "        throw 'Не удалось отключить тестовый диск';" ^
    "    };" ^
    "};" ^
    "$folder = Get-Item -LiteralPath $env:TEST_DIR;" ^
    "if ($folder.Parent.FullName -ne [IO.Path]::GetTempPath().TrimEnd('\') -or $folder.Name -notlike 'lab1_*') {" ^
    "    throw 'Неверный путь тестовой папки';" ^
    "};" ^
    "Remove-Item -LiteralPath $folder.FullName -Recurse -Force;"
exit /b %ERRORLEVEL%
