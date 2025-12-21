#!/bin/bash
# Clarissa AI - Screenshot Capture for App Store
# Captures screenshots from iOS Simulators for App Store submission

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENSHOTS_DIR="$SCRIPT_DIR/../screenshots"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[SCREENSHOT]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Create screenshot directories
mkdir -p "$SCREENSHOTS_DIR/iPhone-6.9"
mkdir -p "$SCREENSHOTS_DIR/iPhone-6.5"
mkdir -p "$SCREENSHOTS_DIR/iPad-13"

# Required device simulators (boot these first in Xcode)
# iPhone 16 Pro Max = 6.9" display (1320 x 2868)
# iPhone 15 Pro Max = 6.7" display (alternative)
# iPhone 14 Pro Max = 6.7" display (alternative) 
# iPad Pro 13" = 2064 x 2752

log "📱 Available Simulators:"
xcrun simctl list devices available | grep -E "(iPhone|iPad)" | head -20

echo ""
log "To capture screenshots manually:"
echo ""
echo "1. Open Simulator with the app running"
echo "2. Press Cmd+S to save screenshot"
echo "3. Screenshots are saved to ~/Desktop by default"
echo ""
echo "Or use these commands after booting a simulator:"
echo ""
echo "  # Boot iPhone 16 Pro Max (6.9\")"
echo "  xcrun simctl boot \"iPhone 16 Pro Max\""
echo ""
echo "  # Take screenshot"
echo "  xcrun simctl io booted screenshot ~/Desktop/screenshot.png"
echo ""

log "Suggested screenshots for App Store:"
echo ""
echo "  1. welcome.png     - Empty state with welcome message"
echo "  2. conversation.png - Active chat with AI responses"  
echo "  3. tools.png       - Calendar/contacts tool in action"
echo "  4. settings.png    - Settings screen"
echo "  5. voice.png       - Voice mode (optional)"
echo ""

log "After capturing, move screenshots to:"
echo "  $SCREENSHOTS_DIR/iPhone-6.9/"
echo "  $SCREENSHOTS_DIR/iPhone-6.5/"
echo "  $SCREENSHOTS_DIR/iPad-13/"

