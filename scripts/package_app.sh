#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="DiskVisualizer"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "=== Packaging DiskVisualizer into macOS .app Bundle ==="

# Step 1: Generate App Icon
echo "[1/5] Generating App Icon..."
mkdir -p "${PROJECT_DIR}/Packaging"
# generate_icon.swift writes to a relative "Packaging/" path — run it from the
# project root so the icons land in the right place regardless of caller cwd.
(cd "${PROJECT_DIR}" && swift "${PROJECT_DIR}/Packaging/generate_icon.swift")
if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns "${PROJECT_DIR}/Packaging/AppIcon.iconset" -o "${PROJECT_DIR}/Packaging/AppIcon.icns"
    echo "Compiled AppIcon.icns successfully."
else
    echo "Warning: iconutil not found. Skipping icns compilation."
fi

# Step 2: Build Swift Package in Release Mode
echo "[2/5] Building release executable with SPM..."
(cd "${PROJECT_DIR}" && swift build -c release)

RELEASE_BIN="$(cd "${PROJECT_DIR}" && swift build -c release --show-bin-path)/DiskVisualizer"

if [ ! -f "${RELEASE_BIN}" ]; then
    echo "Error: Release binary not found at ${RELEASE_BIN}"
    exit 1
fi

# Step 3: Create Bundle Directory Structure
echo "[3/5] Assembling ${APP_NAME}.app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy Binary
cp "${RELEASE_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
if [ -f "${PROJECT_DIR}/Packaging/Info.plist" ]; then
    cp "${PROJECT_DIR}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    echo "Error: Info.plist missing!"
    exit 1
fi

# Copy AppIcon.icns
if [ -f "${PROJECT_DIR}/Packaging/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Packaging/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Create PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Step 4: Code Sign the Application Bundle
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "[4/5] Code signing application bundle (Ad-hoc)..."
else
    echo "[4/5] Code signing application bundle with identity: ${SIGNING_IDENTITY}..."
fi
codesign --force --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"

# Step 5: Verify Bundle & Create Distribution Zip
echo "[5/5] Verifying bundle..."
codesign --verify --verbose "${APP_BUNDLE}"

(cd "${BUILD_DIR}" && zip -q -r "${APP_NAME}.zip" "${APP_NAME}.app")

echo "=== SUCCESS! ==="
echo "Application bundle created at: ${APP_BUNDLE}"
echo "Zip archive created at: ${BUILD_DIR}/${APP_NAME}.zip"
