#!/bin/zsh
# Build eqpop.app (needs only the Command Line Tools). Output: build/eqpop.app, then:  open build/eqpop.app
set -e
cd "$(dirname "$0")"
VERSION=$(sed -n 's/^let eqpopVersion = "\(.*\)"/\1/p' Sources/eqpop/Store.swift)
swift build -c release
APP=build/eqpop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/eqpop "$APP/Contents/MacOS/eqpop"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>eqpop</string>
<key>CFBundleIdentifier</key><string>io.github.aliperdehan.eqpop</string>
<key>CFBundleExecutable</key><string>eqpop</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP ($VERSION)"
