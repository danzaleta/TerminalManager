#!/bin/zsh
set -e

# Configuration
APP_NAME="TerminalManager"
EXECUTABLE_NAME="TerminalManager"
WIDGET_NAME="TerminalManagerWidget"
BUNDLE_ID="com.danzaleta.terminalmanager"
VERSION="1.0.0"

# Directories
BUILD_DIR=".build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLUGINS_DIR="${CONTENTS_DIR}/PlugIns"
WIDGET_APPEX_DIR="${PLUGINS_DIR}/${WIDGET_NAME}.appex"
WIDGET_CONTENTS_DIR="${WIDGET_APPEX_DIR}/Contents"
WIDGET_MACOS_DIR="${WIDGET_CONTENTS_DIR}/MacOS"

echo "Building Swift package (App & Widget)..."
swift build -c release

echo "Creating App Bundle structure..."
mkdir -p "${MAC_OS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${WIDGET_MACOS_DIR}"

echo "Copying main executable..."
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${MAC_OS_DIR}/"

echo "Copying main Info.plist..."
cp "Info.plist" "${CONTENTS_DIR}/"

echo "Assembling Widget Extension..."
cp "${BUILD_DIR}/${WIDGET_NAME}" "${WIDGET_MACOS_DIR}/"
cp "TerminalManagerWidget-Info.plist" "${WIDGET_CONTENTS_DIR}/Info.plist"

echo "Code signing Widget Extension with Sandbox entitlements..."
codesign --force -s - --entitlements "TerminalManagerWidget.entitlements" "${WIDGET_APPEX_DIR}"

echo "Code signing Main App Bundle..."
codesign --force -s - "${APP_DIR}"

echo "App Bundle created at ${APP_DIR}"

# Copy to ~/Applications and register widget
if [ -d "$HOME/Applications" ]; then
    echo "Updating ~/Applications/${APP_NAME}.app..."
    rm -rf "$HOME/Applications/${APP_NAME}.app"
    cp -r "${APP_DIR}" "$HOME/Applications/"
    
    echo "Registering with LaunchServices..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/${APP_NAME}.app" || true
    
    echo "Registering Desktop Widget with macOS..."
    pluginkit -a "$HOME/Applications/${APP_NAME}.app/Contents/PlugIns/${WIDGET_NAME}.appex" || true
    
    echo "Flushing WidgetKit cache..."
    killall chronod 2>/dev/null || true
    
    echo "App & Widget available in ~/Applications/${APP_NAME}.app"
fi
