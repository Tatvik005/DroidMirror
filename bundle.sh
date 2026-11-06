#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/build/DroidMirror.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "=== Packaging DroidMirror.app ==="

# 1. Build release binary
echo "[-] Building release executable..."
swift build -c release

# 2. Create bundle structure
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 3. Copy binaries and assets
cp -f "${DIR}/.build/release/DroidMirror" "${MACOS_DIR}/DroidMirror"
chmod +x "${MACOS_DIR}/DroidMirror"

cp -f "${DIR}/Resources/adb" "${RESOURCES_DIR}/adb"
chmod +x "${RESOURCES_DIR}/adb"

cp -f "${DIR}/Resources/scrcpy-server.jar" "${RESOURCES_DIR}/scrcpy-server.jar"

if [ -f "${DIR}/Resources/AppIcon.icns" ]; then
    cp -f "${DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "${DIR}/Resources/AppIcon.png" ]; then
    cp -f "${DIR}/Resources/AppIcon.png" "${RESOURCES_DIR}/AppIcon.png"
fi

# 4. Generate Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DroidMirror</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.droidmirror.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DroidMirror</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 5. Ad-hoc codesign
codesign --force --deep --sign - "${APP_DIR}"

echo "[+] Application bundle created successfully at: ${APP_DIR}"
echo "You can launch it via: open '${APP_DIR}'"
