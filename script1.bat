@echo off
setlocal
chcp 65001 >nul

set "DIR_PATH=%~1"
set "X_LIMIT=%~2"
set "BACKUP_DIR=%~3"
if not defined X_LIMIT set "X_LIMIT=70"
if not defined BACKUP_DIR set "BACKUP_DIR=.\backup"

if not defined DIR_PATH (
    echo Использование: script1.bat папка [порог] [папка_архивов]
    exit /b 1
)

if not exist "%DIR_PATH%\" (
    echo Укажите существующую папку: script1.bat папка [порог] [папка_архивов]
    exit /b 1
)

set "DISK_ROOT=%~d1\"
powershell.exe -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "if ($env:X_LIMIT -notmatch '^[0-9]+$') {" ^
    "    Write-Output 'Порог должен быть целым числом от 0 до 100.';" ^
    "    exit 1;" ^
    "};" ^
    "$X_LIMIT = [int]$env:X_LIMIT;" ^
    "if ($X_LIMIT -gt 100) {" ^
    "    Write-Output 'Порог должен быть от 0 до 100.';" ^
    "    exit 1;" ^
    "};" ^
    "$disk = [IO.DriveInfo]::new($env:DISK_ROOT);" ^
    "$ALL_AREA = $disk.TotalSize;" ^
    "$USED_AREA = $ALL_AREA - $disk.TotalFreeSpace;" ^
    "$PERCENT = [math]::Ceiling(100 * $USED_AREA / $ALL_AREA);" ^
    "Write-Output ('Заполнение: ' + $PERCENT + '%%. Порог: ' + $X_LIMIT + '%%.');" ^
    "if ($PERCENT -le $X_LIMIT) {" ^
    "    Write-Output 'Очистка не требуется.';" ^
    "    exit 0;" ^
    "};" ^
    "$BYTES_TO_DELETE = $USED_AREA - $ALL_AREA * $X_LIMIT / 100;" ^
    "$DIR_PATH = (Get-Item -LiteralPath $env:DIR_PATH).FullName.TrimEnd('\');" ^
    "$BACKUP_DIR = [IO.Path]::GetFullPath($env:BACKUP_DIR);" ^
    "$NEEDED_FILES = Get-ChildItem -LiteralPath ($DIR_PATH + '\') -File -Recurse -Force | Sort-Object LastWriteTime;" ^
    "$FILES_TO_ARCHIVE = @();" ^
    "$SELECTED_BYTES = 0;" ^
    "foreach ($file in $NEEDED_FILES) {" ^
    "    if ($SELECTED_BYTES -ge $BYTES_TO_DELETE) {" ^
    "        break;" ^
    "    };" ^
    "    $SELECTED_BYTES += $file.Length;" ^
    "    $relativePath = $file.FullName.Substring($DIR_PATH.Length + 1);" ^
    "    $relativePath = $relativePath.Replace('\', '/');" ^
    "    $FILES_TO_ARCHIVE += './' + $relativePath;" ^
    "};" ^
    "if ($SELECTED_BYTES -lt $BYTES_TO_DELETE) {" ^
    "    Write-Output 'Недостаточно файлов для достижения порога.';" ^
    "    exit 1;" ^
    "};" ^
    "New-Item -ItemType Directory -Path $BACKUP_DIR -Force > $null;" ^
    "$TAR_OPT = '-z';" ^
    "$EXTENSION = 'gz';" ^
    "if ($env:LAB1_MAX_COMPRESSION -eq '1') {" ^
    "    $TAR_OPT = '--lzma';" ^
    "    $EXTENSION = 'lzma';" ^
    "};" ^
    "$date = Get-Date -Format 'yyyyMMdd_HHmmss_fff';" ^
    "$ARCHIVE_NAME = Join-Path $BACKUP_DIR ('archive_' + $date + '.tar.' + $EXTENSION);" ^
    "tar.exe -c $TAR_OPT -f $ARCHIVE_NAME -C ($DIR_PATH + '\') -- @FILES_TO_ARCHIVE;" ^
    "if ($LASTEXITCODE -ne 0) {" ^
    "    Write-Output 'Ошибка архивации. Файлы не удалены.';" ^
    "    exit 1;" ^
    "};" ^
    "foreach ($file in $FILES_TO_ARCHIVE) {" ^
    "    Remove-Item -LiteralPath (Join-Path $DIR_PATH $file) -Force;" ^
    "};" ^
    "$PERCENT = [math]::Ceiling(100 * ($disk.TotalSize - $disk.TotalFreeSpace) / $disk.TotalSize);" ^
    "Write-Output ('Архив: ' + $ARCHIVE_NAME);" ^
    "Write-Output ('Удалено файлов: ' + $FILES_TO_ARCHIVE.Count + '. Заполнение: ' + $PERCENT + '%%.');" ^
    "if ($PERCENT -gt $X_LIMIT) {" ^
    "    Write-Output 'Порог не достигнут.';" ^
    "    exit 1;" ^
    "};"
exit /b %ERRORLEVEL%
