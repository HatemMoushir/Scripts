#!/bin/bash
# ==========================================================
# Oracle Forms 11g Custom Bean Build & Smart Deploy
# By Hatem Moushir 2026 v2.0
# ==========================================================
# ==========================================================
# CONFIGURATION NOTES (IMPORTANT)
# ==========================================================
#
# 1️⃣ Ensure ORACLE_HOME is exported before running:
#    export ORACLE_HOME=/u01/app/oracle/middleware
#
# 2️⃣ Required library for Forms 11g:
#    $ORACLE_HOME/forms/java/frmall.jar
#
# 3️⃣ DO NOT package frmall.jar inside your custom jar.
#
# 4️⃣ After updating JAR:
#    Sometimes you may need to clear server cache:
#
#    $DOMAIN_HOME/servers/WLS_FORMS/tmp
#    $DOMAIN_HOME/servers/WLS_FORMS/cache
#
#    Or restart WLS_FORMS if needed.
#
# 5️⃣ In formsweb.cfg:
#    archive=mybean.jar,frmall.jar
#
# ==========================================================

############################
# Prevent double execution #
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
WORK_DIR=/export/home/oracle/MCSD
SRC_JAVA=$WORK_DIR/java_src
BUILD_DIR=$WORK_DIR/build/classes
SRC_JARS=$WORK_DIR/SOURCES/jars
VERSIONS_DIR=$WORK_DIR/VERSIONS/$(date +"%y%m%d_%H%M")
LOG_FILE=$WORK_DIR/logs/jar_build_$(date +"%y%m%d_%H%M").log

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
# Compile (Smart Classpath)
############################
if [ -z "$ORACLE_HOME" ]; then
  echo "ORACLE_HOME not set!"
  exit 1
fi

FORMS_LIB=$ORACLE_HOME/forms/java/frmall.jar
CUSTOM_LIBS=$(find "$SRC_JARS" -name "*.jar" ! -name "$JAR_NAME" | tr '\n' ':')
CLASSPATH="$FORMS_LIB:$CUSTOM_LIBS"

javac -cp "$CLASSPATH" -d "$BUILD_DIR" "${FILES[@]}" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  echo "Compilation failed."
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

############################################################
# Smart Hash Check
############################################################
TARGET_LINK="$ORACLE_HOME/forms/java/$JAR_NAME"

NEW_HASH=$(sha256sum "$NEW_JAR" | awk '{print $1}')
OLD_HASH=""

if [ -f "$TARGET_LINK" ]; then
  OLD_HASH=$(sha256sum "$TARGET_LINK" | awk '{print $1}')
fi

if [ "$NEW_HASH" = "$OLD_HASH" ]; then
  echo "No changes detected. Skipping deploy."
  exit 0
fi

############################################################
# Backup for rollback
############################################################
PREVIOUS_TARGET=""
if [ -L "$TARGET_LINK" ]; then
  PREVIOUS_TARGET=$(readlink -f "$TARGET_LINK")
elif [ -f "$TARGET_LINK" ]; then
  PREVIOUS_TARGET="$TARGET_LINK"
fi

############################################################
# Deploy via Symlink
############################################################
ln -sf "$NEW_JAR" "$TARGET_LINK"

############################################################
# Controlled Restart
############################################################
if [ -z "$DOMAIN_HOME" ]; then
  echo "DOMAIN_HOME not set!"
  exit 1
fi

$DOMAIN_HOME/bin/stopManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
sleep 10

$DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
sleep 20

if ! pgrep -f "Dweblogic.Name=WLS_FORMS" > /dev/null; then
  echo "Restart failed. Rolling back..."

  if [ -n "$PREVIOUS_TARGET" ]; then
    ln -sf "$PREVIOUS_TARGET" "$TARGET_LINK"
    $DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
  fi

  exit 1
fi

echo "Deployment completed successfully." | tee -a "$LOG_FILE"
exit 0
