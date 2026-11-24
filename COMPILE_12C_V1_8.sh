#!/bin/bash
# By Hatem Moushir 2026 (9 apr 2026) v1.8
# 24/5/2026

 shopt -s nullglob nocaseglob

#======================================
# Connection string 
CONN_STR="user_comp/pass@test"
# WORKing DIR
RUN_FOLDER=company
BACKUP_FLDR=company_BACKUP
#======================================
TIMESTAMP=$(date +"%y_%m_%d__%H_%M")
start_date=$(date)
#####CUR_FLDR=/export/home/weblogic/company/LAST_FORMS/test2
CUR_FLDR=`pwd`
CUR_FLDR_name=$(basename `pwd`)
#======================================

WORK_DIR=/export/home/weblogic/$RUN_FOLDER
BACKUP_DIR=$WORK_DIR/$BACKUP_FLDR
REPORTS_DIR=$WORK_DIR/REPORTS
REPORTS_BACKUP_DIR=$WORK_DIR/$BACKUP_FLDR/REPORTS
VERSIONS_DIR=$WORK_DIR/VERSIONS/$TIMESTAMP

#======================================
# source folders
SOURCES=$WORK_DIR/SOURCES
SRC_FORMS=$WORK_DIR/SOURCES/forms
SRC_REPORTS=$WORK_DIR/SOURCES/reports
SRC_PLLS=$WORK_DIR/SOURCES/plls

#======================================

# Errors  folders

CONFLICT_DIR="$WORK_DIR/logs/$CUR_FLDR_name/conflicts/conflicts_$TIMESTAMP"
ERRORS_DIR="$WORK_DIR/logs/$CUR_FLDR_name/errors/errors_$TIMESTAMP"
FRM_ERR_succ="$ERRORS_DIR/FRM_ERR_success"
FRM_ERR_fail="$ERRORS_DIR/FRM_ERR_fail"
PLL_ERR_fail="$ERRORS_DIR/PLL_ERR_fail"
REP_ERR_fail="$ERRORS_DIR/REP_ERR_fail"

# Local Errors  folders

Local_CONFLICT_DIR="$CUR_FLDR/logs/conflicts"
Local_ERRORS_DIR="$CUR_FLDR/logs/errors"

#Local_CONFLICT_DIR="$CUR_FLDR/logs/conflicts/conflicts_$TIMESTAMP"
#Local_ERRORS_DIR="$CUR_FLDR/logs/errors/errors_$TIMESTAMP"
#Local_FRM_ERR_succ="$Local_ERRORS_DIR/FRM_ERR_success"
#Local_FRM_ERR_fail="$Local_ERRORS_DIR/FRM_ERR_fail"
#Local_PLL_ERR_fail="$Local_ERRORS_DIR/PLL_ERR_fail"
#Local_REP_ERR_fail="$Local_ERRORS_DIR/REP_ERR_fail"

#======================================
#logs
LOG_FILE=$WORK_DIR/logs/$CUR_FLDR_name/run_$TIMESTAMP.log
FRM_FAIL_LOG_FILE=$ERRORS_DIR/forms_err_log_$TIMESTAMP.log
REP_FAIL_LOG_FILE=$ERRORS_DIR/reports_err_log_$TIMESTAMP.log
PLL_FAIL_LOG_FILE=$ERRORS_DIR/pll_err_log_$TIMESTAMP.log

CONFLICT_LOG_FILE=$CONFLICT_DIR/conflicts_log_$TIMESTAMP.log

#Local logs
#Local_LOG_FILE=$CUR_FLDR/logs/run_$TIMESTAMP.log
#Local_FRM_FAIL_LOG_FILE=$Local_ERRORS_DIR/forms_err_log_$TIMESTAMP.log
#Local_REP_FAIL_LOG_FILE=$Local_ERRORS_DIR/reports_err_log_$TIMESTAMP.log
#Local_PLL_FAIL_LOG_FILE=$Local_ERRORS_DIR/pll_err_log_$TIMESTAMP.log

#CONFLICT_LOG_FILE=Local_CONFLICT_DIR/conflicts_log_$TIMESTAMP.log

#======================================
# Oracle enviroment
ORACLE_HOME=/u01/app/weblogic/product/12.2.1.4/Oracle_Home
DOMAIN_HOME=$ORACLE_HOME/user_projects/domains/base_domain
LD_LIBRARY_PATH=$ORACLE_HOME/lib
REPORTS_PATH=$REPORTS_DIR:$ORACLE_HOME/reports:$ORACLE_HOME/reports/templates
TNS_ADMIN=$DOMAIN_HOME/config/fmwconfig
PATH=$ORACLE_HOME/jdk1.8.0_441/bin:$ORACLE_HOME/bin:$PATH

#======================================
# Create directories if not exist
mkdir -p "$WORK_DIR" "$REPORTS_DIR" 
mkdir -p "$BACKUP_DIR" "$REPORTS_BACKUP_DIR"
mkdir -p "$VERSIONS_DIR" "$SOURCES"
mkdir -p "$SRC_FORMS" "$SRC_REPORTS" "$SRC_PLLS"
mkdir -p "$(dirname $LOG_FILE)"
mkdir -p "$ERRORS_DIR" "$Local_ERRORS_DIR"
mkdir -p "$CONFLICT_DIR" "$Local_CONFLICT_DIR"
mkdir -p "$FRM_ERR_succ" "$FRM_ERR_fail" "$REP_ERR_fail" "$PLL_ERR_fail" 

#======================================

echo "=== Compile Run Started at $(date) ===" >> "$LOG_FILE"

files_renamed=0
compiled_forms=0; skipped_forms=0
compiled_reports=0; skipped_reports=0
compiled_plls=0; skipped_plls=0
forms_errors=0
reports_errors=0
pll_errors=0
errors=0
#======================================

# Rename CUR_FLDR to lowercase

echo "== ****************Rename *********************** == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

declare -A seen
found_uppercase=false

for f in "$CUR_FLDR"/*.fmb "$CUR_FLDR"/*.rdf; do
    [ -e "$f" ] || continue
    [ -f "$f" ] || continue
 
   ### [[ "$f" == "$CONFLICT_DIR" ]] && continue
   ### [[ "${f,,}" == *.pll ]] && continue
   ### [[ "${f,,}" == *.olb ]] && continue


   filename=$(basename "$f")
   name="${filename%.*}"
   ext="${filename##*.}"
	
	if [ "$name" = "$filename" ]; then
		upper_name=$(echo "$filename" | tr '[:lower:]' '[:upper:]')
		newname="$upper_name"	
	else
		upper_name=$(echo "$name" | tr '[:lower:]' '[:upper:]')
		lower_ext=$(echo "$ext"  | tr '[:upper:]' '[:lower:]')
		newname="${upper_name}.${lower_ext}"	

	fi
##########################################
if [ "$filename" != "$newname" ]; then	
	if [ -n "${seen[$newname]}" ]; then

	     first="${seen[$newname]}"
             if [ -e "$CUR_FLDR/$newname" ]; then
	         mv "$CUR_FLDR/$newname" "$CONFLICT_DIR/$first"
	        echo "Conflict :$first moved to conflicts/" |  tee -a "$LOG_FILE"
	        echo "Conflict :$first moved to conflicts/"   >> "$LOG_FILE"
	     fi

	     mv "$f" "$CONFLICT_DIR/$filename"
	     echo "Conflict : $filename moved to conflicts/" |  tee -a "$LOG_FILE"
	     echo "Conflict : $filename moved to conflicts/"  >> "$LOG_FILE"

	else
	    seen[$newname]="$filename"
	    target="$CUR_FLDR/$newname"
            found_uppercase=true	

		if [ -e "$CUR_FLDR/$newname" ]; then
	         	mv "$CUR_FLDR/$newname" "$CONFLICT_DIR/$newname"
	        	echo "Conflict :$newname moved to conflicts/" |  tee -a "$LOG_FILE"
			echo "Conflict :$newname moved to conflicts/"  >> "$LOG_FILE"
	     	fi

		mv "$f" "$target"
		echo "Renamed $filename ->$newname   " | tee -a "$LOG_FILE"
		echo "Renamed $filename ->$newname   "  >> "$LOG_FILE"
		files_renamed=$((files_renamed+1))

	fi
fi

done
##########################################
if [ "$found_uppercase" = false ]; then
    echo "No mismatch case Letters in files names found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi
echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

   # newname=$(basename "$f" | tr '[:upper:]' '[:lower:]')
   #  if [ "$(basename "$f")" != "$newname" ]; then
   #      mv "$f" "$CUR_FLDR/$newname"
   #      echo "Renamed $(basename "$f") -> $newname" | tee -a "$LOG_FILE"
   #  fi

echo "== ********************************************* == " | tee -a "$LOG_FILE"
#======================================

# 1-  Compile PLL to PLX

echo "== ********Compile PLL to PLX  at $(date) ****************** == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

found_plls=false
for i in "$CUR_FLDR"/*.pll; do
    [ -e "$i" ] || continue; found_plls=true
    if [ ! -s "$i" ]; then
        echo "Skipping empty/corrupted PLL $(basename $i)" | tee -a "$LOG_FILE"
        skipped_plls=$((skipped_plls+1)); continue
    fi

    echo "Compiling PLL $(basename $i)" | tee -a "$LOG_FILE"
    chmod 0777 "$i"

	err="$(basename "${i%.pll}.err")"


    sudo -u weblogic $DOMAIN_HOME/config/fmwconfig/components/FORMS/instances/forms1/bin/frmcmp_batch.sh \
        module="$i" userid=$CONN_STR batch=yes module_type=library compile_all=yes \
        >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        plx="$(basename "${i%.pll}.plx")"
        cp "$CUR_FLDR/$plx" "$VERSIONS_DIR/$plx"
	rm "$BACKUP_DIR/$plx"
        cp "$CUR_FLDR/$plx" "$BACKUP_DIR/$plx"
        mv "$CUR_FLDR/$plx" "$WORK_DIR/$plx" 
        # copy source PLL (not move)
        cp "$i" "$SRC_PLLS/$(basename $i)"
        cp "$i" "$VERSIONS_DIR/$(basename $i)"
        compiled_plls=$((compiled_plls+1))
    else
	 mv  "$CUR_FLDR/$err" "$PLL_ERR_fail/$err"
        echo "==> Error compiling PLL $(basename $i)" | tee -a "$LOG_FILE"
        echo "$(basename $i)" | tee -a "$PLL_FAIL_LOG_FILE"

        pll_errors=$((pll_errors+1))
    fi
done
if [ "$found_plls" = false ]; then
    echo "No PLL files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi
echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

#======================================

# 2- Compile Forms to FMX
echo "== ********Compile Forms to FMX  at $(date) ***************** == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

found_forms=false
for i in "$CUR_FLDR"/*.fmb; do
    [ -e "$i" ] || continue; found_forms=true
    if [ ! -s "$i" ]; then
        echo "Skipping empty/corrupted form $(basename $i)" | tee -a "$LOG_FILE"
        skipped_forms=$((skipped_forms+1)); continue
    fi

	fmx="$(basename "${i%.fmb}.fmx")"
	err="$(basename "${i%.fmb}.err")"


    echo "Compiling form $(basename $i)" | tee -a "$LOG_FILE"
    chmod 0777 "$i"
    sudo -u weblogic $DOMAIN_HOME/config/fmwconfig/components/FORMS/instances/forms1/bin/frmcmp_batch.sh \
        module="$i" userid=$CONN_STR batch=yes Module_Type=FORM compile_all=yes \
        >> "$LOG_FILE" 2>&1


    if [ $? -eq 0 ]; then
        cp "$CUR_FLDR/$fmx" "$VERSIONS_DIR/$fmx"
	rm "$BACKUP_DIR/$fmx"
        cp "$CUR_FLDR/$fmx" "$BACKUP_DIR/$fmx"
        mv "$CUR_FLDR/$fmx" "$WORK_DIR/$fmx" 
        #mv "$i" "$SRC_FORMS/$(basename $i)"

	if [ "$(basename $i)" = "INITIAL_company.fmb" ]; then
        	cp "$i" "$SRC_FORMS/$(basename "$i")"
    	else
        	mv "$i" "$SRC_FORMS/$(basename "$i")"
    	fi

        mv  "$CUR_FLDR/$err" "$FRM_ERR_succ/$err"
        cp "$SRC_FORMS/$(basename $i)" "$VERSIONS_DIR/$(basename $i)"
        compiled_forms=$((compiled_forms+1))
    else
	#mv "$i" "$FRM_ERR_fail/$(basename $i)"

	if [ "$(basename $i)" = "INITIAL_company.fmb" ]; then
        	cp "$i" "$FRM_ERR_fail/$(basename $i)"
    	else
        	mv "$i" "$FRM_ERR_fail/$(basename $i)"
    	fi

	mv  "$CUR_FLDR/$err" "$FRM_ERR_fail/$err"
        echo "==> Error compiling form $(basename $i)" | tee -a "$LOG_FILE"
	echo "$(basename $i)" | tee -a "$FRM_FAIL_LOG_FILE"
        forms_errors=$((forms_errors+1))
    fi



done
if [ "$found_forms" = false ]; then
    echo "No FMB files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi

echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

#======================================
# 3 Compile Reports  to REP
echo "== *******************Compile Reports  to REP  at $(date) ******* == " | tee -a "$LOG_FILE"
echo "== ****** == " | tee -a "$LOG_FILE"

found_reports=false

#####./$ORACLE_HOME/bin/reports.sh

for i in "$CUR_FLDR"/*.rdf; do
    [ -e "$i" ] || continue; found_reports=true
    if [ ! -s "$i" ]; then
        echo "Skipping empty/corrupted report $(basename $i)" | tee -a "$LOG_FILE"
        skipped_reports=$((skipped_reports+1)); continue
    fi

 rep="$(basename "${i%.rdf}.rep")"
 plg="$(basename "${i%.rdf}.plg")"

    echo "Compiling report $(basename $i)" | tee -a "$LOG_FILE"
    chmod 0777 "$i"


# sudo -E -u weblogic ./compile_report.sh $i $CONN_STR 

sudo -E -u weblogic \
ORACLE_HOME=$ORACLE_HOME \
DOMAIN_HOME=$DOMAIN_HOME \
LD_LIBRARY_PATH=$LD_LIBRARY_PATH \
REPORTS_PATH=$REPORTS_PATH \
TNS_ADMIN=$TNS_ADMIN \
PATH=$PATH \
$ORACLE_HOME/bin/rwconverter.sh \
userid=$CONN_STR \
batch=yes \
source="$i" \
stype=rdffile \
dtype=repfile \
compile_all=yes \
overwrite=yes \
        >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        cp "$CUR_FLDR/$rep" "$VERSIONS_DIR/$rep"
	rm "$BACKUP_DIR/$rep"
        cp "$CUR_FLDR/$rep" "$BACKUP_DIR/$rep"
        mv "$CUR_FLDR/$rep" "$REPORTS_DIR/$rep" 
        mv "$i" "$SRC_REPORTS/$(basename $i)"
        cp "$SRC_REPORTS/$(basename $i)" "$VERSIONS_DIR/$(basename $i)"
        compiled_reports=$((compiled_reports+1))
    else
	mv "$i" "$REP_ERR_fail/$(basename $i)"
        echo "==> Error compiling report $(basename $i)" | tee -a "$LOG_FILE"
        echo "$(basename $i)" | tee -a "$REP_FAIL_LOG_FILE"
        reports_errors=$((reports_errors+1))
    fi

# mv "$CUR_FLDR/$plg" "$REPORTS_DIR"

done



if [ "$found_reports" = false ]; then
    echo "No RDF files found in $CUR_FLDR" | tee -a "$LOG_FILE"
fi


echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "== ********************************************* == " | tee -a "$LOG_FILE"
echo "=== Compile Run Finished at $(date) ===" | tee -a "$LOG_FILE"

echo "=== Compile Run Finished at $(date) [ start date at $start_date ]==="  >> "$LOG_FILE"

echo "--- Summary ---" >> "$LOG_FILE"

echo "Files renamed: $files_renamed" >> "$LOG_FILE"
echo "PLLs compiled: $compiled_plls" >> "$LOG_FILE"
echo "PLLs skipped: $skipped_plls" >> "$LOG_FILE"
echo "PLLs errors: $pll_errors" >> "$LOG_FILE"
echo "Forms compiled: $compiled_forms" >> "$LOG_FILE"
echo "Forms skipped: $skipped_forms" >> "$LOG_FILE"
echo "Forms errors: $forms_errors" >> "$LOG_FILE"
echo "Reports compiled: $compiled_reports" >> "$LOG_FILE"
echo "Reports skipped: $skipped_reports" >> "$LOG_FILE"
echo "reports errors: $reports_errors" >> "$LOG_FILE"


cp "$LOG_FILE" "$CUR_FLDR/logs/"
cp -r "$ERRORS_DIR" "$Local_ERRORS_DIR"
cp -r "$CONFLICT_DIR" "$Local_CONFLICT_DIR"

#--------------------------------------------------

if (( files_renamed == 0 && compiled_forms == 0 && skipped_forms == 0 &&
      compiled_reports == 0 && skipped_reports == 0 &&
      compiled_plls == 0 && skipped_plls == 0 &&
      forms_errors == 0 && reports_errors == 0 && pll_errors == 0 )); then
    errors=0
else
    errors=1
fi
#--------------------------------------------------

if [ "${errors:-0}" -gt 0 ]; then exit 1; else exit 0; fi
