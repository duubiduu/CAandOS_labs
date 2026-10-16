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

teardown_env() {
    umount "$MNT_DIR" 2>/dev/null
    rm -rf "$TEST_DIR"
}

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo -e "[ОШИБКА] Скрипт $MAIN_SCRIPT не найден!"
    exit 1
fi

echo -e "[ТЕСТ 1] Папка заполнена на 40% при пороге 50%"
setup_env "1000m"
head -c 200M /dev/zero > "$LOG_DIR/file_old.log"
head -c 200M /dev/zero > "$LOG_DIR/file_new.log"
touch -t "202401011200" "$LOG_DIR/file_old.log"

$MAIN_SCRIPT "$LOG_DIR" 50 "$BACKUP_DIR"

if [ -z "$(ls -A "$BACKUP_DIR")" ] && [ $(ls -1 "$LOG_DIR" | wc -l) -eq 2 ]; then
    echo -e "  Тест пройден. Алгоритм верно проигнорировал папку и сохранил файлы"
else
    echo -e "  Ошибка! Запустилась очистка, хотя переполнения нет"
fi
teardown_env

echo -e "[ТЕСТ 2] Превышение лимита на 80 Мб. Жадный алгоритм должен удалить строго 1 старый файл"
setup_env "600m"
head -c 150M /dev/zero > "$LOG_DIR/file_1_old.log"
head -c 350M /dev/zero > "$LOG_DIR/file_2_new.log"
touch -t "202401011200" "$LOG_DIR/file_1_old.log"
touch -t "202401021200" "$LOG_DIR/file_2_new.log"

$MAIN_SCRIPT "$LOG_DIR" 70 "$BACKUP_DIR"

if [ ! -f "$LOG_DIR/file_1_old.log" ] && [ -f "$LOG_DIR/file_2_new.log" ]; then
    echo -e "  [OK] Тест пройден! Умная остановка: удален только 1 старый файл, новый на 350Мб спасен"
else
    echo -e "  [FAIL] Ошибка жадного алгоритма отбора!"
fi
teardown_env

echo -e "[ТЕСТ 3] Каскадный набор: для устранения перебора требуется накопление 3-х файлов"
setup_env "500m"
head -c 90M /dev/zero > "$LOG_DIR/log_old_A.log"
head -c 90M /dev/zero > "$LOG_DIR/log_old_B.log"
head -c 90M /dev/zero > "$LOG_DIR/log_old_C.log"
head -c 180M /dev/zero > "$LOG_DIR/log_new_D.log"
touch -t "202401011200" "$LOG_DIR/log_old_A.log"
touch -t "202401011300" "$LOG_DIR/log_old_B.log"
touch -t "202401011400" "$LOG_DIR/log_old_C.log"
touch -t "202401021200" "$LOG_DIR/log_new_D.log"

$MAIN_SCRIPT "$LOG_DIR" 40 "$BACKUP_DIR"

if [ $(ls -1 "$LOG_DIR" | wc -l) -eq 1 ] && [ -f "$LOG_DIR/log_new_D.log" ]; then
    echo -e "  [OK] Тест пройден! Алгоритм успешно накопил веса из 3-х файлов и очистил дельту"
else
    echo -e "  [FAIL] Ошибка каскадного накопления веса!"
fi
teardown_env

echo -e "[ТЕСТ 4] Максимальное компрессионное сжатие (LAB1_MAX_COMPRESSION=1)"
setup_env "600m"
head -c 200M /dev/zero > "$LOG_DIR/heavy_old.log"
head -c 250M /dev/zero > "$LOG_DIR/heavy_new.log"
touch -t "202401011200" "$LOG_DIR/heavy_old.log"

export LAB1_MAX_COMPRESSION=1
$MAIN_SCRIPT "$LOG_DIR" 50 "$BACKUP_DIR"
unset LAB1_MAX_COMPRESSION

if ls "$BACKUP_DIR"/*.xz 1> /dev/null 2>&1; then
    echo -e "  [OK] Тест пройден! Создан высокоплотный архив формата .tar.xz (LZMA)"
else
    echo -e "  [FAIL] Ошибка! Бонусный архив .tar.xz не обнаружен"
fi
teardown_env

echo -e "[ТЕСТ 5] Граничный случай: Занято ровно 70% при лимите 70%"
setup_env "1000m"
head -c 400M /dev/zero > "$LOG_DIR/border_1.log"
head -c 300M /dev/zero > "$LOG_DIR/border_2.log"

$MAIN_SCRIPT "$LOG_DIR" 70 "$BACKUP_DIR"

if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
    echo -e "  [OK] Тест пройден! Точное совпадение не вызвало ложной очистки"
else
    echo -e "  [FAIL] Ошибка! Скрипт сработал при равенстве, нарушая условие '-gt'"
fi
teardown_env

echo -e "[ТЕСТ 6] Проверка надежности кода: Сканирование абсолютно пустой папки логов"
setup_env "500m"

$MAIN_SCRIPT "$LOG_DIR" 20 "$BACKUP_DIR" > /dev/null
if [ $? -eq 0 ]; then
    echo -e "  [OK] Тест пройден! Скрипт корректно обработал отсутствие файлов"
else
    echo -e "  [FAIL] Критический сбой: скрипт упал при анализе пустой папки!"
fi
teardown_env
