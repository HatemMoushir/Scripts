#!/bin/bash
# By Hatem Moushir 2026 v1.1
shopt -s nocaseglob

NOW_DATE=$(date +"%y%m%d_%H%M")
CUR_FLDR=/export/home/oracle/Company/tmp
WORK_DIR=/export/home/oracle/Company
REPORTS_DIR=$WORK_DIR/REPORTS
VERSIONS_DIR=$WORK_DIR/VERSIONS/$NOW_DATE
LOG_FILE=$WORK_DIR/logs/run_$NOW_DATE.log

# فولدرات المصادر
SRC_FORMS=$WORK_DIR/SOURCES/forms
SRC_REPORTS=$WORK_DIR/SOURCES/reports
SRC_PLLS=$WORK_DIR/SOURCES/plls

# Connection string في متغير واحد
CONN_STR="user/pass@dbtest"

mkdir -p "$VERSIONS_DIR" "$REPORTS_DIR" "$SRC_FORMS" "$SRC_REPORTS" "$SRC_PLLS"
mkdir -p "$(dirname $LOG_FILE)"

echo "=== Compile Run Started at $(date) ===" >> "$LOG_FILE"

compiled_forms=0; skipped_forms=0
compiled_reports=0; skipped_reports=0
compiled_plls=0; skipped_plls=0
errors=0

# Rename إلى lowercase داخل CUR_FLDR
for f in "$CUR_FLDR"/*; do
    [ -e "$f" ] || continue
    newname=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    if [ "$(basename "$f")" != "$newname" ]; then
        mv "$f" "$CUR_FLDR/$newname"
        echo "Renamed $(basename "$f") -> $newname" | tee -a "$LOG_FILE"
    fi
done

# 1️⃣ Compile PLL → PLX
found_plls=false
for i in "$CUR_FLDR"/*.pll; do
    [ -e "$i" ] || continue
    found_plls=true
    if [ ! -s "$i" ]; then
        echo "Skipping empty/corrupted PLL $(basename $i)" | tee -a "$LOG_FILE"
        skipped_plls=$((skipped_plls+1))
        continue
    fi

    echo "Compiling PLL $(basename $i)" | tee -a "$LOG_FILE"
    chmod 0777 "$i"
    sudo -u oracle $ORACLE_HOME/bin/frmcmp_batch.sh \
        module="$i" userid=$CONN_STR batch=yes moduletype=library compile_all=yes window_state=minimize \
        >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        plx="$(basename "${i%.pll}.plx")"
        mv "$CUR_FLDR/$plx" "$WORK_DIR/$plx"
        cp "$WORK_DIR/$plx" "$VERSIONS_DIR/$plx"
        cp "$i" "$SRC_PLLS/$(basename $i)"
        cp "$i" "$VERSIONS_DIR/$(basename $i)"
        compiled_plls=$((compiled_plls+1))
    else
        echo "Error compiling PLL $(basename $i)" | tee -a "$LOG_FILE"
        errors=$((errors+1))
    fi
done

if [ "$found_plls" = false ]; then
    echo "No PLL files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi

# 2️⃣ Compile Forms → FMX
found_forms=false
for i in "$CUR_FLDR"/*.fmb; do
    [ -e "$i" ] || continue
    found_forms=true
    if [ ! -s "$i" ]; then
        echo "Skipping empty/corrupted form $(basename $i)" | tee -a "$LOG_FILE"
        skipped_forms=$((skipped_forms+1))
        continue
    fi

    echo "Compiling form $(basename $i)" | tee -a "$LOG_FILE"
    chmod 0777 "$i"
    sudo -u oracle $ORACLE_HOME/bin/frmcmp_batch.sh \
        module="$i" userid=$CONN_STR batch=yes compile_all=yes window_state=minimize \
        >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        fmx="$(basename "${i%.fmb}.fmx")"
        mv "$CUR_FLDR/$fmx" "$WORK_DIR/$fmx"
        cp "$WORK_DIR/$fmx" "$VERSIONS_DIR/$fmx"
        mv "$i" "$SRC_FORMS/$(basename $i)"
        cp "$SRC_FORMS/$(basename $i)" "$VERSIONS_DIR/$(basename $i)"
        compiled_forms=$((compiled_forms+1))
    else
        echo "Error compiling form $(basename $i)" | tee -a "$LOG_FILE"
        errors=$((errors+1))
    fi
done

if [ "$found_forms" = false ]; then
    echo "No FMB files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi

# 3️⃣ Compile Reports → REP
found_reports=false
for i in "$CUR_FLDR"/*.rdf; do
    [ -e "$i" ] || continue
    found_reports=true
    if [ ! -s "$i" ]; then
        echo "Skipping empty/corrupted report $(basename $i)" | tee -a "$LOG_FILE"
        skipped_reports=$((skipped_reports+1))
        continue
    fi

    echo "Compiling report $(basename $i)" | tee -a "$LOG_FILE"
    chmod 0777 "$i"
    sudo -u oracle $ORACLE_HOME/bin/rwconverter.sh \
        userid=$CONN_STR batch=yes source="$i" stype=rdffile dtype=repfile compile_all=yes overwrite=yes \
        >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        rep="$(basename "${i%.rdf}.rep")"
        mv "$CUR_FLDR/$rep" "$REPORTS_DIR/$rep"
        cp "$REPORTS_DIR/$rep" "$VERSIONS_DIR/$rep"
        mv "$i" "$SRC_REPORTS/$(basename $i)"
        cp "$SRC_REPORTS/$(basename $i)" "$VERSIONS_DIR/$(basename $i)"
        compiled_reports=$((compiled_reports+1))
    else
        echo "Error compiling report $(basename $i)" | tee -a "$LOG_FILE"
        errors=$((errors+1))
    fi
done

if [ "$found_reports" = false ]; then
    echo "No RDF files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi

echo "=== Compile Run Finished at $(date) ===" >> "$LOG_FILE"
echo "--- Summary ---" >> "$LOG_FILE"
echo "PLLs compiled: $compiled_plls" >> "$LOG_FILE"
echo "PLLs skipped: $skipped_plls" >> "$LOG_FILE"
echo "Forms compiled: $compiled_forms" >> "$LOG_FILE"
echo "Forms skipped: $skipped_forms" >> "$LOG_FILE"
echo "Reports compiled: $compiled_reports" >> "$LOG_FILE"
echo "Reports skipped: $skipped_reports" >> "$LOG_FILE"
echo "Errors: $errors" >> "$LOG_FILE"

if [ $errors -gt 0 ]; then
    exit 1
else
    exit 0
fi
