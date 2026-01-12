#!/bin/bash

# Build script for TextReplacer app

APP_NAME="TextReplacer"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Compile Swift files
echo "Compiling Swift files..."
swiftc -o "$MACOS/$APP_NAME" \
    main.swift \
    AppDelegate.swift \
    InputMonitor.swift \
    ReplacementManager.swift \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices \
    -framework IOKit

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Copy Info.plist
cp Info.plist "$CONTENTS/"

echo "✓ Build successful!"
echo "✓ App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install to Applications folder:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "⚠️  Important: You need to grant Input Monitoring permission"
echo "    System Settings > Privacy & Security > Input Monitoring"
