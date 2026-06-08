#!/bin/bash
set -e

echo "Building RaccoonTools..."
swift build -c release 2>&1

APP_NAME="RaccoonTools.app"
APP_DIR="$APP_NAME/Contents/MacOS"
RES_DIR="$APP_NAME/Contents/Resources"
mkdir -p "$APP_DIR" "$RES_DIR"

cp .build/release/RaccoonTools "$APP_DIR/RaccoonTools"
cp Resources/Info.plist "$APP_NAME/Contents/Info.plist"

# Copy icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$RES_DIR/AppIcon.icns"
fi

# Copy raccoon image for menu bar (optional)
if [ -f "Resources/raccoon.jpg" ]; then
    cp "Resources/raccoon.jpg" "$RES_DIR/raccoon.jpg"
fi

# Kill running instance
killall RaccoonTools 2>/dev/null || true
sleep 0.5

# Install to /Applications
echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME"
cp -R "$APP_NAME" "/Applications/$APP_NAME"

# Relaunch
open "/Applications/$APP_NAME"

echo ""
echo "Build complete!"
echo "Installed: /Applications/$APP_NAME"
echo "Run with: open /Applications/RaccoonTools.app"
echo ""
echo "To start at login: System Settings > General > Login Items > add RaccoonTools"
