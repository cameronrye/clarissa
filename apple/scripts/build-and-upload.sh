#!/bin/bash
# Clarissa AI - Build and Upload to TestFlight
# Usage: ./build-and-upload.sh [ios|macos|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
PROJECT_DIR="$SCRIPT_DIR/../Clarissa"
ARCHIVE_DIR="$HOME/Desktop/Clarissa-Archives"
EXPORT_DIR="$HOME/Desktop/Clarissa-Exports"

# Load environment variables from .env
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

# App Store Connect API credentials (from .env)
API_KEY="${APP_STORE_CONNECT_KEY_ID:?Missing APP_STORE_CONNECT_KEY_ID in .env}"
API_ISSUER="${APP_STORE_CONNECT_ISSUER_ID:?Missing APP_STORE_CONNECT_ISSUER_ID in .env}"
TEAM_ID="${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID in .env}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Create directories
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

build_ios() {
    log "Building iOS archive..."
    
    xcodebuild archive \
        -project "$PROJECT_DIR/Clarissa.xcodeproj" \
        -scheme Clarissa \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE_DIR/Clarissa-iOS.xcarchive" \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="$TEAM_ID"

    log "Exporting iOS IPA..."
    
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_DIR/Clarissa-iOS.xcarchive" \
        -exportPath "$EXPORT_DIR/iOS" \
        -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
        -allowProvisioningUpdates
    
    # Note: xcodebuild -exportArchive with ExportOptions.plist already uploads to App Store Connect
    # The export step above handles both IPA creation and upload when destination=upload

    log "iOS build uploaded successfully!"
}

build_macos() {
    log "Building macOS archive..."
    
    xcodebuild archive \
        -project "$PROJECT_DIR/Clarissa.xcodeproj" \
        -scheme Clarissa \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_DIR/Clarissa-macOS.xcarchive" \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="$TEAM_ID"

    log "Exporting macOS app..."
    
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_DIR/Clarissa-macOS.xcarchive" \
        -exportPath "$EXPORT_DIR/macOS" \
        -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
        -allowProvisioningUpdates
    
    # Note: xcodebuild -exportArchive with ExportOptions.plist already uploads to App Store Connect

    log "macOS build uploaded successfully!"
}

case "${1:-all}" in
    ios)
        build_ios
        ;;
    macos)
        build_macos
        ;;
    all)
        build_ios
        build_macos
        ;;
    *)
        echo "Usage: $0 [ios|macos|all]"
        exit 1
        ;;
esac

log "🎉 Build complete! Check App Store Connect for processing status."
log "Once processed, go to TestFlight to add the build to your beta group."

