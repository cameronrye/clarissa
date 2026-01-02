#!/bin/bash
# Clarissa AI - Build and Upload to TestFlight
# Usage: ./build-and-upload.sh [ios|macos|all]
#
# Required .env variables:
#   APPLE_TEAM_ID              - Your Apple Developer Team ID
#   APP_STORE_CONNECT_KEY_ID   - App Store Connect API Key ID
#   APP_STORE_CONNECT_ISSUER_ID - App Store Connect Issuer ID
#   APP_STORE_CONNECT_KEY_PATH - Path to .p8 API key file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
PROJECT_DIR="$SCRIPT_DIR/../Clarissa"
ARCHIVE_DIR="$HOME/Desktop/Clarissa-Archives"
EXPORT_DIR="$HOME/Desktop/Clarissa-Exports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Load environment variables from .env
if [ -f "$ROOT_DIR/.env" ]; then
    log "Loading .env from $ROOT_DIR/.env"
    set -a
    source "$ROOT_DIR/.env"
    set +a
else
    error ".env file not found at $ROOT_DIR/.env"
fi

# App Store Connect API credentials (from .env)
TEAM_ID="${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID in .env}"
API_KEY="${APP_STORE_CONNECT_KEY_ID:?Missing APP_STORE_CONNECT_KEY_ID in .env}"
API_ISSUER="${APP_STORE_CONNECT_ISSUER_ID:?Missing APP_STORE_CONNECT_ISSUER_ID in .env}"
API_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-$HOME/.private_keys/AuthKey_${API_KEY}.p8}"

# Expand tilde in path
API_KEY_PATH="${API_KEY_PATH/#\~/$HOME}"

# Verify API key file exists
if [ ! -f "$API_KEY_PATH" ]; then
    error "API key file not found: $API_KEY_PATH

Download your .p8 key from App Store Connect:
  https://appstoreconnect.apple.com/access/integrations/api

Then save it to: $API_KEY_PATH"
fi

log "Using Team ID: $TEAM_ID"
log "Using API Key: $API_KEY"
log "Using API Key File: $API_KEY_PATH"

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
        -authenticationKeyPath "$API_KEY_PATH" \
        -authenticationKeyID "$API_KEY" \
        -authenticationKeyIssuerID "$API_ISSUER" \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="$TEAM_ID"

    log "Exporting and uploading iOS to TestFlight..."

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_DIR/Clarissa-iOS.xcarchive" \
        -exportPath "$EXPORT_DIR/iOS" \
        -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$API_KEY_PATH" \
        -authenticationKeyID "$API_KEY" \
        -authenticationKeyIssuerID "$API_ISSUER"

    log "iOS build uploaded to TestFlight!"
}

build_macos() {
    log "Building macOS archive..."

    xcodebuild archive \
        -project "$PROJECT_DIR/Clarissa.xcodeproj" \
        -scheme Clarissa \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_DIR/Clarissa-macOS.xcarchive" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$API_KEY_PATH" \
        -authenticationKeyID "$API_KEY" \
        -authenticationKeyIssuerID "$API_ISSUER" \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="$TEAM_ID"

    log "Exporting and uploading macOS to TestFlight..."

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_DIR/Clarissa-macOS.xcarchive" \
        -exportPath "$EXPORT_DIR/macOS" \
        -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$API_KEY_PATH" \
        -authenticationKeyID "$API_KEY" \
        -authenticationKeyIssuerID "$API_ISSUER"

    log "macOS build uploaded to TestFlight!"
}

show_usage() {
    echo "Usage: $0 [ios|macos|all]"
    echo ""
    echo "Commands:"
    echo "  ios    - Build and upload iOS to TestFlight"
    echo "  macos  - Build and upload macOS to TestFlight"
    echo "  all    - Build and upload both (default)"
    echo ""
    echo "Required .env variables:"
    echo "  APPLE_TEAM_ID                - Your Apple Developer Team ID"
    echo "  APP_STORE_CONNECT_KEY_ID     - App Store Connect API Key ID"
    echo "  APP_STORE_CONNECT_ISSUER_ID  - App Store Connect Issuer ID"
    echo "  APP_STORE_CONNECT_KEY_PATH   - Path to .p8 API key file"
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
    -h|--help|help)
        show_usage
        exit 0
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

log "Build complete! Check App Store Connect for processing status."
log "Builds typically appear in TestFlight within 15-30 minutes."
