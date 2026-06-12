#!/bin/bash
# =============================================================================
# Maya Commander – ARM64 Release Build Script
# =============================================================================
# This script builds Maya Commander for Apple Silicon (arm64) only.
#
# Usage:
#   ./scripts/build.sh
#
# The built .app will be placed in:
#   build/Release/Maya Commander.app
#
# Requirements:
#   - Xcode 26.5+ (with command-line tools)
#   - Apple Silicon Mac
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="Maya Commander"
SCHEME="Maya Commander"
CONFIGURATION="Release"
ARCHS="arm64"
BUILD_DIR="${PROJECT_DIR}/build"

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Pre-flight checks -------------------------------------------------------
echo -e "${YELLOW}🔍 Checking system requirements...${NC}"

# Check for Xcode
if ! xcode-select -p &>/dev/null; then
    echo -e "${RED}❌ Xcode command-line tools not found. Please install Xcode from the Mac App Store.${NC}"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}❌ This script requires an Apple Silicon (arm64) Mac.${NC}"
    echo -e "${RED}   Detected architecture: ${ARCH}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Architecture: ${ARCH}${NC}"
echo -e "${GREEN}✅ Xcode: $(xcodebuild -version 2>/dev/null | head -1)${NC}"

# --- Clean previous build ----------------------------------------------------
echo -e "${YELLOW}🧹 Cleaning previous build...${NC}"
rm -rf "${BUILD_DIR}"

# --- Build -------------------------------------------------------------------
echo -e "${YELLOW}🔨 Building ${PROJECT_NAME} (${CONFIGURATION}, arm64)...${NC}"

xcodebuild \
    -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -arch "${ARCHS}" \
    ONLY_ACTIVE_ARCH=NO \
    clean build \
    | while IFS= read -r line; do
        # Filter out noisy intermediate output, show warnings/errors
        if echo "$line" | grep -qE "^(\*\* (BUILD|CHECK|CLEAN|CREATE) )|(error:|warning:|note:)"; then
            echo "$line"
        fi
    done

# Check build result
BUILD_RESULT="${PIPESTATUS[0]}"
if [ "${BUILD_RESULT}" -ne 0 ]; then
    echo -e "${RED}❌ Build failed with exit code ${BUILD_RESULT}${NC}"
    exit "${BUILD_RESULT}"
fi

# --- Copy .app to build directory --------------------------------------------
echo -e "${YELLOW}📦 Copying .app bundle...${NC}"

# Find the built .app
APP_SOURCE="${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}/${PROJECT_NAME}.app"
APP_DEST="${BUILD_DIR}/${PROJECT_NAME}.app"

mkdir -p "$(dirname "${APP_DEST}")"
cp -R "${APP_SOURCE}" "${APP_DEST}"
rm -rf "${BUILD_DIR}/DerivedData"

# --- Verify architecture ----------------------------------------------------
echo -e "${YELLOW}🔬 Verifying binary architecture...${NC}"
BINARY="${APP_DEST}/Contents/MacOS/${PROJECT_NAME}"
if [ -f "${BINARY}" ]; then
    FILE_ARCH=$(lipo -archs "${BINARY}" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✅ Binary architecture: ${FILE_ARCH}${NC}"

    if [ "${FILE_ARCH}" != "arm64" ]; then
        echo -e "${RED}⚠️  Warning: Binary architecture is '${FILE_ARCH}', expected 'arm64'${NC}"
    fi
else
    echo -e "${RED}❌ Binary not found at: ${BINARY}${NC}"
    exit 1
fi

# --- Done --------------------------------------------------------------------
echo ""
echo -e "${GREEN}✅ Build complete!${NC}"
echo -e "${GREEN}📁 App location: ${APP_DEST}${NC}"
echo ""
echo -e "${YELLOW}To install, run:${NC}"
echo -e "  ${GREEN}cp -R '${APP_DEST}' /Applications/${NC}"
echo ""

# Open the build directory in Finder
open "${BUILD_DIR}"
