#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="DiskVisualizer"
FINAL_DMG="${BUILD_DIR}/${APP_NAME}-Installer.dmg"
TMP_DMG="${BUILD_DIR}/${APP_NAME}_tmp.dmg"
STAGING_DIR="${BUILD_DIR}/dmg_staging"
MOUNT_POINT="/Volumes/${APP_NAME}"
MOUNTED=""

echo "=== Creating macOS Drag-to-Applications DMG Installer ==="

# Check notarization requirements early if NOTARIZE=true
if [ "${NOTARIZE}" = "true" ]; then
    if [ -z "${DEVELOPER_ID_APPLICATION}" ] || [ -z "${KEYCHAIN_PROFILE}" ]; then
        echo "Error: NOTARIZE=true requires both DEVELOPER_ID_APPLICATION and KEYCHAIN_PROFILE environment variables."
        exit 1
    fi
fi

# Cleanup trap ensures unmounting and temp folder removal on exit/failure
cleanup() {
    local exit_code=$?
    if [ -n "${MOUNTED}" ]; then
        hdiutil detach "${MOUNTED}" 2>/dev/null || hdiutil detach -force "${MOUNTED}" 2>/dev/null || true
    fi
    rm -rf "${STAGING_DIR}" "${TMP_DMG}" 2>/dev/null || true
}
trap cleanup EXIT

# Step 1: Package the .app bundle
echo "[1/5] Building application bundle..."
"${SCRIPT_DIR}/package_app.sh"

if [ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    echo "Error: ${APP_NAME}.app bundle not found in ${BUILD_DIR}"
    exit 1
fi

# Step 2: Prepare Staging Folder
echo "[2/5] Staging installer layout..."
rm -rf "${STAGING_DIR}" "${TMP_DMG}" "${FINAL_DMG}"
mkdir -p "${STAGING_DIR}"

cp -R "${BUILD_DIR}/${APP_NAME}.app" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# Step 3: Create & Mount Temporary Read/Write DMG
echo "[3/5] Creating temporary read/write disk image..."
hdiutil create -srcfolder "${STAGING_DIR}" -volname "${APP_NAME}" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "${TMP_DMG}"
# Mount at the default /Volumes/<name> so Finder's `tell disk` resolves — a
# custom mountpoint breaks disk-name lookup. Detach any stale volume first.
hdiutil detach "${MOUNT_POINT}" 2>/dev/null || true
hdiutil attach "${TMP_DMG}"
MOUNTED="${MOUNT_POINT}"

# Step 4: Configure Finder Window Layout
echo "[4/5] Configuring Finder layout..."
osascript <<EOF 2>/dev/null || echo "Warning: Finder layout customization skipped (headless environment or layout error)."
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 1000, 480}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 12
        set position of item "${APP_NAME}.app" of container window to {160, 170}
        set position of item "Applications" of container window to {440, 170}
        update without registering applications
        delay 3
        close container window
    end tell
end tell
EOF

# Step 5: Convert to Compressed Distribution DMG
echo "[5/5] Compressing final installer DMG..."
hdiutil detach "${MOUNTED}"
MOUNTED=""
hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"

# Notarization pass if requested
if [ "${NOTARIZE}" = "true" ]; then
    echo "=== Notarizing DMG Installer ==="
    echo "Submitting DMG to Apple Notary Service..."
    xcrun notarytool submit "${FINAL_DMG}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait
    
    echo "Stapling notarization ticket..."
    xcrun stapler staple "${FINAL_DMG}"
    
    echo "Validating notarization ticket..."
    xcrun stapler validate "${FINAL_DMG}"
    spctl --assess --type open --context context:primary-signature "${FINAL_DMG}"
    echo "Notarization and validation successful!"
else
    echo "Note: Ad-hoc local build. Web downloads require Gatekeeper bypass (right-click -> Open)."
fi

echo "=== SUCCESS! ==="
echo "Installer DMG created at: ${FINAL_DMG}"
