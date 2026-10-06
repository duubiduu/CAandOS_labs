#!/bin/bash

if [ "$1" != "--in-ns" ]; then
    unshare -Urm "$0" --in-ns
    exit $?
fi

MAIN_SCRIPT="$(pwd)/script1.sh"
TEST_DIR="$(pwd)/test_env"
MNT_DIR="$TEST_DIR/mnt"
LOG_DIR="$MNT_DIR/log"
BACKUP_DIR="$MNT_DIR/backup"

setup_env() {
    local fs_size=$1
    umount "$MNT_DIR" 2>/dev/null
    rm -rf "$TEST_DIR"
    mkdir -p "$MNT_DIR"
    mount -t tmpfs -o size="$fs_size" tmpfs "$MNT_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"
}

generate_files() {
    local count=${1:-6}
    echo "       -> Генерируем $(($count * 100)) MB логов..."
    
    for i in $(seq "$count" -1 1); do
        head -c 100M /dev/zero > "$LOG_DIR/file_$i.log"
        day=$(printf "%02d" $((30 - i)))
        touch -t "202401${day}1200" "$LOG_DIR/file_$i.log"
    done
}

teardown_env() {
    umount "$MNT_DIR" 2>/dev/null
    rm -rf "$TEST_DIR"
}

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "[ОШИБКА] Скрипт $MAIN_SCRIPT не найден!"
    exit 1
fi

echo -e "\nТЕСТ 1: Базовое срабатывание (Порог превышен)"
setup_env "800m"
generate_files 6
$MAIN_SCRIPT "$LOG_DIR" 70 "$BACKUP_DIR"
if ls "$BACKUP_DIR"/*.tar.gz 1> /dev/null 2>&1; then
    echo "  [OK] Архив успешно создан."
else
    echo "  [FAIL] Архив не найден!"
fi
teardown_env

echo -e "\nТЕСТ 2: Порог НЕ превышен"
setup_env "800m"
generate_files 6
$MAIN_SCRIPT "$LOG_DIR" 90 "$BACKUP_DIR"
if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
    echo "  [OK] Папка backup осталась пустой."
else
    echo "  [FAIL] Скрипт создал архив, хотя не должен был!"
fi
teardown_env

echo -e "\nТЕСТ 3: Фильтрация по дате (самые старые)"
setup_env "800m"
generate_files 6
$MAIN_SCRIPT "$LOG_DIR" 50 "$BACKUP_DIR"
if [ ! -f "$LOG_DIR/file_6.log" ] && [ -f "$LOG_DIR/file_1.log" ]; then
    echo "  [OK] Самые старые файлы удалены, новые остались."
else
    echo "  [FAIL] Ошибка фильтрации по дате!"
fi
teardown_env

echo -e "\nТЕСТ 4: Сжатие LZMA (LAB1_MAX_COMPRESSION=1)"
setup_env "800m"
generate_files 6
export LAB1_MAX_COMPRESSION=1
$MAIN_SCRIPT "$LOG_DIR" 70 "$BACKUP_DIR"
unset LAB1_MAX_COMPRESSION
if ls "$BACKUP_DIR"/*.xz 1> /dev/null 2>&1; then
    echo "  [OK] Архив LZMA (.tar.xz) успешно создан!"
else
    echo "  [FAIL] Архив .tar.xz не найден."
fi
teardown_env

echo -e "\nТЕСТ 5: Точное совпадение порога (Граничный тест)"
setup_env "800m"
generate_files 6
$MAIN_SCRIPT "$LOG_DIR" 75 "$BACKUP_DIR"
if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
    echo "  [OK] При точном совпадении (75%) архивация не запустилась."
else
    echo "  [FAIL] Скрипт сработал при точном совпадении!"
fi
teardown_env

echo -e "\nТЕСТ 6: Отсутствие прав или файлов (Безопасность)"
setup_env "800m"
$MAIN_SCRIPT "$LOG_DIR" 70 "$BACKUP_DIR" > /dev/null
if [ $? -eq 0 ]; then
    echo "  [OK] Скрипт корректно обработал пустую папку."
else
    echo "  [FAIL] Скрипт упал с ошибкой!"
fi
teardown_env

echo -e "\nТЕСТ 7: Умная остановка удаления"
setup_env "1000m"
generate_files 8
$MAIN_SCRIPT "$LOG_DIR" 60 "$BACKUP_DIR"
remaining_files=$(ls -1 "$LOG_DIR" | wc -l)
if [ "$remaining_files" -eq 5 ]; then
    echo "  [OK] Скрипт остановился вовремя! Осталось файлов: $remaining_files (ожидалось 5)."
else
    echo "  [FAIL] Ожидалось 5 файлов, но осталось $remaining_files!"
fi
teardown_env

echo -e "\n[INFO] Все тесты завершены!"
