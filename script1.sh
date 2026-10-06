DIR_PATH=$1
X_LIMIT=$2
BACKUP_DIR=${3:-./backup}

if [ ! -d "$DIR_PATH" ]; then
	echo "Ошибка, папка $DIR_PATH не существует!"
	exit 1
fi

DISK_INFO=$(df "$DIR_PATH" | tail -n 1)
ALL_AREA=$(echo "$DISK_INFO" | awk '{print $2}')
USED_AREA=$(echo "$DISK_INFO" | awk '{print $3}')
PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')

echo "Диск заполнен на $PERCENT% (Занято $((USED_AREA / 1024)) Мб из $((ALL_AREA / 1024)) Мб)"

if [ "$PERCENT" -gt "$X_LIMIT" ]; then
	echo "Превышен порог $X_LIMIT% по заполненности!"
	MAX_USED_AREA=$((ALL_AREA * X_LIMIT / 100))
	KB_TO_DELETE=$((USED_AREA - MAX_USED_AREA))
	BITES_TO_DELETE=$((KB_TO_DELETE * 1024))
	echo "Необходимо освободить $((KB_TO_DELETE / 1024)) Мб"

	mkdir -p "$BACKUP_DIR"

	NEEDED_FILES=$(find "$DIR_PATH" -type f -printf '%T@\t%s\t%p\n' 2>/dev/null | sort -n)
	
	if [ -z "$NEEDED_FILES" ]; then
		echo "Не найдены файлы для очистки!"
		exit 0
	fi
	
	DELETED_BITES=0
	FILES_TO_ARCHIVE=()
	
	while IFS=$'\t' read -r time size path; do
		if [ "$DELETED_BITES" -ge "$BITES_TO_DELETE" ]; then
			break
		fi
		
		DELETED_BITES=$((DELETED_BITES + size))
		FILES_TO_ARCHIVE+=("$path")
	done <<< "$NEEDED_FILES"
	
	if [ ${#FILES_TO_ARCHIVE[@]} -eq 0 ]; then
		echo ""
		exit 0
	fi
	
	TIMING=$(date +%s)
	if [ "$LAB1_MAX_COMPRESSION" = "1" ]; then
		ARCHIVE_NAME="$BACKUP_DIR/archive_$(date +%s).tar.xz"
		TAR_OPT="-cJf" 
	else
		ARCHIVE_NAME="$BACKUP_DIR/archive_$(date +%s).tar.gz"
		TAR_OPT="-czf"
	fi
	
	tar $TAR_OPT "$ARCHIVE_NAME" "${FILES_TO_ARCHIVE[@]}" 2>/dev/null
	TAR_STATUS=$?

	if [ $TAR_STATUS -eq 0 ]; then
		echo "Создан архив $ARCHIVE_NAME"
		rm -f "${FILES_TO_ARCHIVE[@]}"
		echo "Очистка завершена!"
	else
		echo "Ошибка, не удалось создать архив! Операция остановлена, файлы остались нетронуты"
		exit 1
	fi
else
	echo "Порог $X_LIMIT% не превышен. Очистка не требуется"
fi
