# By Hatem Moushir 2026 v1.1
SRC_JARS="$WORK_DIR/SOURCES/jars"
mkdir -p "$SRC_JARS" "$VERSIONS_DIR"

found_jars=false

for i in "$CUR_FLDR"/*.jar; do
  [ -e "$i" ] || continue
  found_jars=true

  fname=$(basename "$i")

  if [ ! -s "$i" ]; then
    echo "Skipping empty/corrupted JAR $fname" | tee -a "$LOG_FILE"
    continue
  fi

  echo "Processing JAR $fname" | tee -a "$LOG_FILE"

  cp "$i" "$SRC_JARS/$fname"
  cp "$i" "$VERSIONS_DIR/$fname"
done

if [ "$found_jars" = false ]; then
  echo "No JAR files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi
