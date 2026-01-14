#!/bin/bash
# Clarissa AI - Automated Screenshot Capture for App Store
# Single script to capture demo screenshots on all platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../Clarissa"
SCREENSHOTS_DIR="$SCRIPT_DIR/../screenshots"
CACHE_DIR="$HOME/Library/Caches/tools.fastlane"
SCREENSHOTS_CACHE="$CACHE_DIR/screenshots"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[SCREENSHOT]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# iOS device configurations for App Store Connect requirements
# Format: "Simulator Name|Output Folder"
# iPhone 6.5": 1284x2778 (iPhone 14 Plus)
# iPad 13": 2064x2752 (iPad Pro 13-inch M5)
IOS_DEVICES=(
    "iPhone 14 Plus|iPhone-6.5"
    "iPad Pro 13-inch (M5)|iPad-13"
)

# Prepare directories for SnapshotHelper
# Usage: prepare_cache [platform]
# platform: ios, macos, watchos, or all (default)
prepare_cache() {
    local platform="${1:-all}"
    log "Preparing screenshot cache for: $platform"

    # Only clear cache entries for the specific platform
    # iOS and watchOS screenshots go to SCREENSHOTS_CACHE with device name prefix
    # macOS screenshots go to container paths
    if [[ "$platform" == "all" ]]; then
        rm -rf "$SCREENSHOTS_CACHE"
        mkdir -p "$SCREENSHOTS_CACHE"
    elif [[ "$platform" == "ios" ]]; then
        # Clear only iOS device screenshots from cache
        for device_config in "${IOS_DEVICES[@]}"; do
            IFS='|' read -r device folder <<< "$device_config"
            rm -f "$SCREENSHOTS_CACHE/$device"-*.png 2>/dev/null || true
        done
        mkdir -p "$SCREENSHOTS_CACHE"
    elif [[ "$platform" == "macos" ]]; then
        # Clear only Mac screenshots from cache
        rm -f "$SCREENSHOTS_CACHE"/Mac-*.png 2>/dev/null || true
        mkdir -p "$SCREENSHOTS_CACHE"
    elif [[ "$platform" == "watchos" ]]; then
        # Clear only Watch screenshots from cache (with or without Clone prefix)
        rm -f "$SCREENSHOTS_CACHE"/*Apple\ Watch*.png 2>/dev/null || true
        mkdir -p "$SCREENSHOTS_CACHE"
    fi

    # Clean macOS container paths only when capturing macOS or all
    if [[ "$platform" == "all" || "$platform" == "macos" ]]; then
        MACOS_CONTAINER="$HOME/Library/Containers/dev.rye.ClarissaUITests.xctrunner/Data/Library/Caches/tools.fastlane/screenshots"
        MACOS_FALLBACK="$HOME/Library/Containers/dev.rye.ClarissaUITests.xctrunner/Data/tmp/fastlane_screenshots"
        rm -rf "$MACOS_CONTAINER" 2>/dev/null || true
        rm -rf "$MACOS_FALLBACK" 2>/dev/null || true
    fi

    # Write language/locale files for SnapshotHelper
    echo "en" > "$CACHE_DIR/language.txt"
    echo "en_US" > "$CACHE_DIR/locale.txt"

    export SIMULATOR_HOST_HOME="$HOME"
}

# Capture iOS/iPad screenshots
capture_ios() {
    log "Capturing iOS screenshots..."
    cd "$PROJECT_DIR"

    for device_config in "${IOS_DEVICES[@]}"; do
        IFS='|' read -r device folder <<< "$device_config"
        info "Capturing on $device..."

        # Run UI tests with demo mode
        xcodebuild -scheme ClarissaUITests \
            -project Clarissa.xcodeproj \
            -destination "platform=iOS Simulator,name=$device" \
            -testLanguage en -testRegion US \
            build test 2>&1 | grep -E "(Test Case|snapshot:|error:)" || true

        log "Completed $device"
    done
}

# Capture macOS screenshots
capture_macos() {
    log "Capturing macOS screenshots..."
    cd "$PROJECT_DIR"

    xcodebuild -scheme ClarissaUITests \
        -project Clarissa.xcodeproj \
        -destination "platform=macOS" \
        build test 2>&1 | grep -E "(Test Case|snapshot:|error:)" || true

    log "Completed macOS"
}

# Capture watchOS screenshots
capture_watchos() {
    log "Capturing watchOS screenshots..."
    cd "$PROJECT_DIR"

    # watchOS simulators require pairing with an iPhone simulator
    local WATCH_DEVICE="Apple Watch Ultra 3 (49mm)"
    local PHONE_DEVICE="iPhone 17 Pro"

    # Get device UDIDs
    local WATCH_UDID
    WATCH_UDID=$(xcrun simctl list devices available | grep "$WATCH_DEVICE" | grep -oE '[A-F0-9-]{36}' | head -1)
    local PHONE_UDID
    PHONE_UDID=$(xcrun simctl list devices available | grep "$PHONE_DEVICE (" | grep -oE '[A-F0-9-]{36}' | head -1)

    if [ -z "$WATCH_UDID" ] || [ -z "$PHONE_UDID" ]; then
        error "Could not find required simulators: $WATCH_DEVICE or $PHONE_DEVICE"
        return 1
    fi

    info "Watch UDID: $WATCH_UDID"
    info "Phone UDID: $PHONE_UDID"

    # Check if pair exists, create if not
    if ! xcrun simctl list pairs | grep -q "$WATCH_UDID"; then
        info "Creating device pair..."
        xcrun simctl pair "$WATCH_UDID" "$PHONE_UDID" 2>/dev/null || true
    fi

    # Boot the iPhone first (required for watch)
    info "Booting $PHONE_DEVICE..."
    xcrun simctl boot "$PHONE_UDID" 2>/dev/null || true

    # Boot the watch
    info "Booting $WATCH_DEVICE..."
    xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true

    # Wait for simulators to be ready
    sleep 3

    # Run watch UI tests
    xcodebuild -scheme ClarissaWatchUITests \
        -project Clarissa.xcodeproj \
        -destination "platform=watchOS Simulator,name=$WATCH_DEVICE" \
        -testLanguage en -testRegion US \
        build test 2>&1 | grep -E "(Test Case|snapshot:|error:)" || true

    # Shutdown simulators to free resources
    info "Shutting down simulators..."
    xcrun simctl shutdown "$WATCH_UDID" 2>/dev/null || true
    xcrun simctl shutdown "$PHONE_UDID" 2>/dev/null || true

    log "Completed watchOS"
}

# Organize screenshots into App Store directories
# Usage: organize_screenshots [platform]
# platform: ios, macos, watchos, or all (default)
organize_screenshots() {
    local platform="${1:-all}"
    log "Organizing screenshots for: $platform"

    # Clean and recreate output directories based on platform
    if [[ "$platform" == "all" || "$platform" == "ios" ]]; then
        for device_config in "${IOS_DEVICES[@]}"; do
            IFS='|' read -r device folder <<< "$device_config"
            rm -rf "${SCREENSHOTS_DIR:?}/${folder:?}"
            mkdir -p "$SCREENSHOTS_DIR/$folder"
        done
    fi
    if [[ "$platform" == "all" || "$platform" == "macos" ]]; then
        rm -rf "${SCREENSHOTS_DIR:?}/macOS"
        mkdir -p "$SCREENSHOTS_DIR/macOS"
    fi
    if [[ "$platform" == "all" || "$platform" == "watchos" ]]; then
        rm -rf "${SCREENSHOTS_DIR:?}/Watch-Ultra"
        mkdir -p "$SCREENSHOTS_DIR/Watch-Ultra"
    fi

    # Collect all screenshot source directories
    # macOS sandboxed apps save to container paths (fallback locations)
    MACOS_CONTAINER="$HOME/Library/Containers/dev.rye.ClarissaUITests.xctrunner/Data/Library/Caches/tools.fastlane/screenshots"
    MACOS_FALLBACK="$HOME/Library/Containers/dev.rye.ClarissaUITests.xctrunner/Data/tmp/fastlane_screenshots"
    SCREENSHOT_SOURCES=("$SCREENSHOTS_CACHE")
    if [ -d "$MACOS_CONTAINER" ]; then
        SCREENSHOT_SOURCES+=("$MACOS_CONTAINER")
    fi
    if [ -d "$MACOS_FALLBACK" ]; then
        SCREENSHOT_SOURCES+=("$MACOS_FALLBACK")
    fi

    # Copy and organize from all source directories (only for specified platform)
    local count=0
    for source_dir in "${SCREENSHOT_SOURCES[@]}"; do
        for file in "$source_dir"/*.png; do
            [ -f "$file" ] || continue
            filename=$(basename "$file")

            # Parse device name from filename (format: DeviceName-ScreenshotName.png)
            # Use matched flag to prevent double-counting files
            matched=false

            # iOS screenshots
            if [[ "$platform" == "all" || "$platform" == "ios" ]]; then
                for device_config in "${IOS_DEVICES[@]}"; do
                    IFS='|' read -r device folder <<< "$device_config"
                    if [[ "$filename" == "$device"* ]]; then
                        screenshot_name="${filename#"$device"-}"
                        cp "$file" "$SCREENSHOTS_DIR/$folder/$screenshot_name"
                        ((count++)) || true
                        matched=true
                        break
                    fi
                done
            fi

            # Mac screenshots
            if [[ "$matched" == false && ("$platform" == "all" || "$platform" == "macos") && "$filename" == Mac-* ]]; then
                screenshot_name="${filename#Mac-}"
                cp "$file" "$SCREENSHOTS_DIR/macOS/$screenshot_name"
                ((count++)) || true
                matched=true
            fi

            # Watch screenshots (handles "Clone N of Apple Watch" prefix from simulator)
            if [[ "$matched" == false && ("$platform" == "all" || "$platform" == "watchos") && "$filename" == *"Apple Watch"* ]]; then
                # Extract screenshot name after device name, stripping optional Clone prefix
                screenshot_name=$(echo "$filename" | sed -E 's/^(Clone [0-9]+ of )?Apple Watch[^-]*-//')
                cp "$file" "$SCREENSHOTS_DIR/Watch-Ultra/$screenshot_name"
                ((count++)) || true
            fi
        done
    done

    if [ $count -eq 0 ]; then
        warn "No screenshots were captured. Check that UI tests are running correctly."
    else
        log "Organized $count screenshots to $SCREENSHOTS_DIR"
    fi
}

# Show what devices are available
list_devices() {
    info "Available iOS Simulators:"
    xcrun simctl list devices available | grep -E "(iPhone|iPad)" | head -15
    echo ""
    info "Available watchOS Simulators:"
    xcrun simctl list devices available | grep -E "Apple Watch" | head -5
    echo ""
    info "Configured devices for capture:"
    for device_config in "${IOS_DEVICES[@]}"; do
        IFS='|' read -r device folder <<< "$device_config"
        echo "  - $device -> $folder/"
    done
    echo "  - Apple Watch Ultra 3 (49mm) -> Watch-Ultra/"
}

# Show usage
usage() {
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  demo      - Capture all platforms (iOS + iPad + macOS + watchOS) - RECOMMENDED"
    echo "  ios       - Capture iOS/iPad screenshots only"
    echo "  macos     - Capture macOS screenshots only"
    echo "  watchos   - Capture watchOS screenshots only"
    echo "  devices   - List available and configured devices"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 demo    # Capture all screenshots for App Store"
    echo "  $0 ios     # Capture only iOS/iPad screenshots"
    echo "  $0 watchos # Capture only watchOS screenshots"
    echo ""
}

# Main
main() {
    case "${1:-help}" in
        demo)
            prepare_cache all
            capture_ios
            capture_macos
            capture_watchos
            organize_screenshots all
            log "Done! Screenshots saved to: $SCREENSHOTS_DIR"
            ;;
        ios)
            prepare_cache ios
            capture_ios
            organize_screenshots ios
            ;;
        macos)
            prepare_cache macos
            capture_macos
            organize_screenshots macos
            ;;
        watchos)
            prepare_cache watchos
            capture_watchos
            organize_screenshots watchos
            ;;
        devices)
            list_devices
            ;;
        help|*)
            usage
            ;;
    esac
}

main "$@"
