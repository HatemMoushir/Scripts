#!/bin/bash
# ==========================================================
# Oracle Forms 12c Custom Bean Build & Smart Deploy
# By Hatem Moushir 2026 v3.0 (12c Edition)
# ==========================================================

############################
# CONFIGURATION NOTES
############################
#
# 1️⃣ Export before run:
#    export ORACLE_HOME=/u01/app/oracle/middleware
#    export DOMAIN_HOME=/u01/app/oracle/config/domains/base_domain
#
# 2️⃣ Forms 12c required library:
#    $ORACLE_HOME/forms/java/frmall.jar
#
# 3️⃣ DO NOT package frmall.jar inside custom jar.
#
# 4️⃣ formsweb.cfg:
#    archive=mybean.jar,frmall.jar
#
# 5️⃣ Managed server name usually:
#    WLS_FORMS
#
############################################################

set -e

############################
# Prevent double execution
############################
LOCK_FILE="/tmp/forms_12c_build.lock"
exec 200>$LOCK_FILE
flock -n 200 || { echo "Another instance running."; exit 1; }

############################
# Validate input
############################
if [ -z "$1" ]; then
  echo "Usage: $0 <jar_name>"
  exit 1
fi

JAR_NAME=$1

############################
# Validate environment
############################
if [ -z "$ORACLE_HOME" ]; then
  echo "ORACLE_HOME not set!"
  exit 1
fi

if [ -z "$DOMAIN_HOME" ]; then
  echo "DOMAIN_HOME not set!"
  exit 1
fi

FORMS_LIB="$ORACLE_HOME/forms/java/frmall.jar"

if [ ! -f "$FORMS_LIB" ]; then
  echo "frmall.jar not found in $FORMS_LIB"
  exit 1
fi

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
# Smart Classpath
############################
CUSTOM_LIBS=$(find "$SRC_JARS" -name "*.jar" ! -name "$JAR_NAME" | tr '\n' ':')
CLASSPATH="$FORMS_LIB:$CUSTOM_LIBS"

echo "Compiling..." >> "$LOG_FILE"

javac -cp "$CLASSPATH" -d "$BUILD_DIR" "${FILES[@]}" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
  echo "Compilation failed."
  exit 1
fi

############################
# Build JAR
############################
jar cvf "$WORK_DIR/$JAR_NAME" -C "$BUILD_DIR" . >> "$LOG_FILE" 2>&1

if [ ! -s "$WORK_DIR/$JAR_NAME" ]; then
  echo "Generated JAR is empty!"
  exit 1
fi

############################
# Copy to repository
############################
cp "$WORK_DIR/$JAR_NAME" "$SRC_JARS/$JAR_NAME"
cp "$WORK_DIR/$JAR_NAME" "$VERSIONS_DIR/$JAR_NAME"

NEW_JAR="$SRC_JARS/$JAR_NAME"
TARGET_LINK="$ORACLE_HOME/forms/java/$JAR_NAME"

############################################################
# Smart SHA256 Hash Check
############################################################
NEW_HASH=$(sha256sum "$NEW_JAR" | awk '{print $1}')
OLD_HASH=""

if [ -f "$TARGET_LINK" ]; then
  OLD_HASH=$(sha256sum "$TARGET_LINK" | awk '{print $1}')
fi

if [ "$NEW_HASH" = "$OLD_HASH" ]; then
  echo "No changes detected. Skipping deploy." | tee -a "$LOG_FILE"
  exit 0
fi

############################################################
# Backup for Rollback
############################################################
PREVIOUS_TARGET=""
BACKUP_DIR="$WORK_DIR/backup_$(date +"%y%m%d_%H%M")"
mkdir -p "$BACKUP_DIR"

if [ -f "$TARGET_LINK" ]; then
  cp "$TARGET_LINK" "$BACKUP_DIR/"
  PREVIOUS_TARGET="$BACKUP_DIR/$JAR_NAME"
fi

############################################################
# Deploy via Symlink
############################################################
ln -sf "$NEW_JAR" "$TARGET_LINK"

############################################################
# Controlled Restart (12c)
############################################################
echo "Stopping WLS_FORMS..." >> "$LOG_FILE"
$DOMAIN_HOME/bin/stopManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
sleep 10

echo "Starting WLS_FORMS..." >> "$LOG_FILE"
$DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
sleep 20

############################################################
# Verify Restart
############################################################
if ! pgrep -f "Dweblogic.Name=WLS_FORMS" > /dev/null; then
  echo "Restart failed. Rolling back..." | tee -a "$LOG_FILE"

  if [ -n "$PREVIOUS_TARGET" ]; then
    cp "$PREVIOUS_TARGET" "$TARGET_LINK"
    $DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS >> "$LOG_FILE" 2>&1
  fi

  exit 1
fi

echo "Deployment completed successfully." | tee -a "$LOG_FILE"
exit 0
