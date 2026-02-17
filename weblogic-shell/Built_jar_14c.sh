#!/bin/bash

# ==========================================================
# Oracle Forms 14c Custom Bean Build & Smart Deploy
# By Hatem Moushir 2026 v3.0
# ==========================================================

# ==========================================================
# CONFIGURATION NOTES (IMPORTANT)
# ==========================================================

# 1️⃣ Ensure ORACLE_HOME is exported before running:
#    export ORACLE_HOME=/u01/app/oracle/middleware

# 2️⃣ Required library for Forms 14c:
#    $ORACLE_HOME/forms/java/frmall.jar

# 3️⃣ DO NOT package frmall.jar inside your custom jar.

# 4️⃣ After updating JAR:
#    Clear cache if needed:
#    $DOMAIN_HOME/servers/WLS_FORMS/tmp
#    $DOMAIN_HOME/servers/WLS_FORMS/cache

# 5️⃣ In formsweb.cfg:
#    archive=mybean.jar,frmall.jar

# ==========================================================

############################
# Prevent double execution
############################
SCRIPT_PATH=$(readlink -f "$0")
RUNNING_COUNT=$(ps -eo pid,args | grep "$SCRIPT_PATH" | grep -v grep | grep -v $$ | wc -l)

if [ "$RUNNING_COUNT" -gt 0 ]; then
  echo "Another instance is running."
  exit 1
fi

############################
# Validate input
############################
if [ -z "$1" ]; then
  echo "Usage: $0 <jar_name>"
  exit 1
fi

JAR_NAME=$1

############################
# Paths
############################
NOW_DATE=$(date +"%y%m%d_%H%M")

WORK_DIR=/export/home/oracle/Company
SRC_JAVA=$WORK_DIR/java_src
BUILD_DIR=$WORK_DIR/build/classes
SRC_JARS=$WORK_DIR/SOURCES/jars
VERSIONS_DIR=$WORK_DIR/VERSIONS/$NOW_DATE
LOG_FILE=$WORK_DIR/logs/jar_build_$NOW_DATE.log

mkdir -p "$BUILD_DIR" "$SRC_JARS" "$VERSIONS_DIR" "$(dirname "$LOG_FILE")"

echo "=== Build Started at $(date) ===" >> "$LOG_FILE"

############################
# Validate Java files
############################
shopt -s nullglob
FILES=("$SRC_JAVA"/*.java)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No Java files found."
  exit 1
fi

############################
# Clean Build
############################
rm -rf "$BUILD_DIR"/*

############################
# Validate ORACLE_HOME
############################
if [ -z "$ORACLE_HOME" ]; then
  echo "ORACLE_HOME not set!"
  exit 1
fi

FORMS_LIB=$ORACLE_HOME/forms/java/frmall.jar

if [ ! -f "$FORMS_LIB" ]; then
  echo "frmall.jar not found in ORACLE_HOME!"
  exit 1
fi

############################
# Smart Classpath
############################
CUSTOM_LIBS=$(find "$SRC_JARS" -name "*.jar" ! -name "$JAR_NAME" | tr '\n' ':')
CLASSPATH="$FORMS_LIB:$CUSTOM_LIBS"

############################
# Compile
############################
javac -cp "$CLASSPATH" -d "$BUILD_DIR" "${FILES[@]}" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  echo "Compilation failed. Check log."
  exit 1
fi

############################
# Build JAR
############################
jar cvf "$WORK_DIR/$JAR_NAME" -C "$BUILD_DIR" . >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  echo "JAR build failed."
  exit 1
fi

############################
# Validate JAR
############################
if [ ! -s "$WORK_DIR/$JAR_NAME" ]; then
  echo "Generated JAR is empty!"
  exit 1
fi

############################
# Copy to storage
############################
cp "$WORK_DIR/$JAR_NAME" "$SRC_JARS/$JAR_NAME"
cp "$WORK_DIR/$JAR_NAME" "$VERSIONS_DIR/$JAR_NAME"

NEW_JAR="$SRC_JARS/$JAR_NAME"
TARGET_LINK="$ORACLE_HOME/forms/java/$JAR_NAME"

############################
# Smart Hash Check
############################
NEW_HASH=$(sha256sum "$NEW_JAR" | awk '{print $1}')
OLD_HASH=""

if [ -f "$TARGET_LINK" ]; then
  OLD_HASH=$(sha256sum "$TARGET_LINK" | awk '{print $1}')
fi

if [ "$NEW_HASH" = "$OLD_HASH" ]; then
  echo "No changes detected. Skipping deploy."
  exit 0
fi

############################
# Backup for rollback
############################
PREVIOUS_TARGET=""
if [ -L "$TARGET_LINK" ]; then
  PREVIOUS_TARGET=$(readlink -f "$TARGET_LINK")
elif [ -f "$TARGET_LINK" ]; then
  PREVIOUS_TARGET="$TARGET_LINK"
fi

############################
# Deploy via Symlink
############################
ln -sf "$NEW_JAR" "$TARGET_LINK"

############################
# Validate DOMAIN_HOME
############################
if [ -z "$DOMAIN_HOME" ]; then
  echo "DOMAIN_HOME not set!"
  exit 1
fi

############################
# Controlled Restart
############################
echo "Stopping WLS_FORMS..." >> "$LOG_FILE"
$DOMAIN_HOME/bin/stopManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
sleep 10

echo "Starting WLS_FORMS..." >> "$LOG_FILE"
$DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
sleep 25

############################
# Restart Validation
############################
if ! pgrep -f "Dweblogic.Name=WLS_FORMS" > /dev/null; then
  echo "Restart failed. Rolling back..." | tee -a "$LOG_FILE"

  if [ -n "$PREVIOUS_TARGET" ]; then
    ln -sf "$PREVIOUS_TARGET" "$TARGET_LINK"
    $DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
  fi

  exit 1
fi

echo "Deployment completed successfully." | tee -a "$LOG_FILE"
exit 0
