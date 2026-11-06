#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${DIR}/Resources"
mkdir -p "${RESOURCES_DIR}"

SCRCPY_SERVER_VERSION="v5.0.1"
SCRCPY_URL="https://github.com/Genymobile/scrcpy/releases/download/${SCRCPY_SERVER_VERSION}/scrcpy-server-${SCRCPY_SERVER_VERSION}"
SCRCPY_TARGET="${RESOURCES_DIR}/scrcpy-server.jar"

echo "=== DroidMirror Mac Setup ==="

# 1. Download scrcpy-server if not present
if [ ! -f "${SCRCPY_TARGET}" ]; then
    echo "[-] Downloading scrcpy-server (${SCRCPY_SERVER_VERSION})..."
    curl -L -o "${SCRCPY_TARGET}" "${SCRCPY_URL}"
    echo "[+] scrcpy-server.jar downloaded successfully."
else
    echo "[+] scrcpy-server.jar already present in Resources/."
fi

# 2. Setup adb binary
ADB_TARGET="${RESOURCES_DIR}/adb"
if [ ! -f "${ADB_TARGET}" ]; then
    # Try finding system adb
    SYSTEM_ADB=$(which adb || true)
    if [ -x "${SYSTEM_ADB}" ]; then
        echo "[+] Found system adb at ${SYSTEM_ADB}. Linking to Resources/adb..."
        cp -f "${SYSTEM_ADB}" "${ADB_TARGET}"
        chmod +x "${ADB_TARGET}"
    elif [ -x "/opt/homebrew/bin/adb" ]; then
        echo "[+] Found Homebrew adb. Copying to Resources/adb..."
        cp -f "/opt/homebrew/bin/adb" "${ADB_TARGET}"
        chmod +x "${ADB_TARGET}"
    else
        echo "[-] Downloading Android platform-tools from Google..."
        TMP_ZIP=$(mktemp /tmp/platform-tools.XXXXXX.zip)
        curl -L -o "${TMP_ZIP}" "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
        unzip -q -j "${TMP_ZIP}" "platform-tools/adb" -d "${RESOURCES_DIR}"
        rm -f "${TMP_ZIP}"
        chmod +x "${ADB_TARGET}"
        echo "[+] adb downloaded and extracted to Resources/adb."
    fi
else
    echo "[+] adb already present in Resources/."
    chmod +x "${ADB_TARGET}"
fi

echo "[+] Verifying bundled components:"
ls -lh "${RESOURCES_DIR}"
"${ADB_TARGET}" version || true

echo "=== Setup Complete! You can now build with 'swift build' ==="
