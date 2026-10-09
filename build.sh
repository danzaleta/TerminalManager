#!/bin/zsh
set -e

# Configuration
APP_NAME="TerminalManager"
EXECUTABLE_NAME="TerminalManager"
BUNDLE_ID="com.danzaleta.terminalmanager"
VERSION="1.0.0"

# Directories
BUILD_DIR=".build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building Swift package..."
swift build -c release

echo "Creating App Bundle structure..."
mkdir -p "${MAC_OS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Copying executable..."
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${MAC_OS_DIR}/"

echo "Copying Info.plist..."
cp "Info.plist" "${CONTENTS_DIR}/"

echo "Code signing..."
codesign --force --deep -s - "${APP_DIR}"

echo "App Bundle created at ${APP_DIR}"

# Optional: Copy to ~/Applications to persist across Kingston unmounts
if [ -d "$HOME/Applications" ]; then
    echo "Copying to ~/Applications..."
    cp -r "${APP_DIR}" "$HOME/Applications/"
    echo "App available in ~/Applications/${APP_NAME}.app"
fi
