#!/bin/bash

# ==========================================================
# Oracle Forms 14c Enterprise Smart Deploy v4.0
# By Hatem Moushir 2026
# ==========================================================
==========================================================

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

set -e

############################
# Config
############################
NOW_DATE=$(date +"%y%m%d_%H%M")
BUILD_NUMBER=$(date +"%Y%m%d%H%M%S")

WORK_DIR=/export/home/oracle/Company
SRC_JAVA=$WORK_DIR/java_src
BUILD_DIR=$WORK_DIR/build/classes
SRC_JARS=$WORK_DIR/SOURCES/jars
VERSIONS_DIR=$WORK_DIR/VERSIONS/$NOW_DATE
LOG_DIR=$WORK_DIR/logs
LOG_FILE=$LOG_DIR/jar_build_$NOW_DATE.log

mkdir -p "$BUILD_DIR" "$SRC_JARS" "$VERSIONS_DIR" "$LOG_DIR"

exec >> "$LOG_FILE" 2>&1

echo "==========================================="
echo "Enterprise Deploy Started: $(date)"
echo "Build Number: $BUILD_NUMBER"
echo "==========================================="

############################
# Validate Environment
############################
[ -z "$ORACLE_HOME" ] && echo "ORACLE_HOME not set" && exit 1
[ -z "$DOMAIN_HOME" ] && echo "DOMAIN_HOME not set" && exit 1

FORMS_LIB=$ORACLE_HOME/forms/java/frmall.jar
[ ! -f "$FORMS_LIB" ] && echo "frmall.jar missing!" && exit 1

############################
# Input
############################
if [ -z "$1" ]; then
  echo "Usage: $0 <jar_name>"
  exit 1
fi

JAR_NAME=$1

############################
# Clean
############################
rm -rf "$BUILD_DIR"/*

############################
# Compile
############################
CUSTOM_LIBS=$(find "$SRC_JARS" -name "*.jar" ! -name "$JAR_NAME" | tr '\n' ':')
CLASSPATH="$FORMS_LIB:$CUSTOM_LIBS"

echo "Compiling..."
javac -cp "$CLASSPATH" -d "$BUILD_DIR" "$SRC_JAVA"/*.java

############################
# Manifest Injection
############################
MANIFEST_FILE=$WORK_DIR/manifest.mf

cat > $MANIFEST_FILE <<EOF
Manifest-Version: 1.0
Implementation-Title: Custom Bean
Implementation-Version: $BUILD_NUMBER
Built-Date: $(date)
Built-By: Hatem Moushir
EOF

############################
# Build JAR
############################
echo "Building JAR..."
jar cfm "$WORK_DIR/$JAR_NAME" "$MANIFEST_FILE" -C "$BUILD_DIR" .

############################
# Hash Check
############################
NEW_HASH=$(sha256sum "$WORK_DIR/$JAR_NAME" | awk '{print $1}')
TARGET_LINK="$ORACLE_HOME/forms/java/$JAR_NAME"

OLD_HASH=""
if [ -f "$TARGET_LINK" ]; then
  OLD_HASH=$(sha256sum "$TARGET_LINK" | awk '{print $1}')
fi

if [ "$NEW_HASH" = "$OLD_HASH" ]; then
  echo "No changes detected."
  exit 0
fi

############################
# Versioned Storage
############################
cp "$WORK_DIR/$JAR_NAME" "$SRC_JARS/$JAR_NAME"
cp "$WORK_DIR/$JAR_NAME" "$VERSIONS_DIR/$JAR_NAME"

PREVIOUS_TARGET=""
if [ -L "$TARGET_LINK" ]; then
  PREVIOUS_TARGET=$(readlink -f "$TARGET_LINK")
elif [ -f "$TARGET_LINK" ]; then
  PREVIOUS_TARGET="$TARGET_LINK"
fi

############################
# Deploy via Symlink
############################
ln -sf "$SRC_JARS/$JAR_NAME" "$TARGET_LINK"

############################
# Cache Purge (Safe)
############################
echo "Cleaning cache..."
rm -rf $DOMAIN_HOME/servers/WLS_FORMS/tmp/*
rm -rf $DOMAIN_HOME/servers/WLS_FORMS/cache/*

############################
# Controlled Restart
############################
echo "Stopping WLS_FORMS..."
$DOMAIN_HOME/bin/stopManagedWebLogic.sh WLS_FORMS

sleep 10

echo "Starting WLS_FORMS..."
$DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS &

sleep 30

############################
# Health Check
############################
echo "Performing health check..."

if pgrep -f "Dweblogic.Name=WLS_FORMS" > /dev/null; then
  echo "Server is UP."
else
  echo "Server failed. Rolling back..."

  if [ -n "$PREVIOUS_TARGET" ]; then
    ln -sf "$PREVIOUS_TARGET" "$TARGET_LINK"
    $DOMAIN_HOME/bin/startManagedWebLogic.sh WLS_FORMS
  fi

  exit 1
fi

echo "==========================================="
echo "Deployment SUCCESS"
echo "==========================================="

exit 0
