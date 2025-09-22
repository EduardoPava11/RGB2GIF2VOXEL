#!/bin/bash
# monitor_device_logs.sh - Real-time performance monitoring from iPhone

set -euo pipefail

echo "================================================"
echo "📊 REAL-TIME PERFORMANCE MONITOR"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Find device
DEVICE_NAME=$(xcrun devicectl list devices | grep -E "iPhone.*Pro" | head -1 | awk '{print $1, $2, $3}' || echo "iPhone")

echo "📱 Monitoring: $DEVICE_NAME"
echo "Press Ctrl+C to stop"
echo ""
echo "Legend:"
echo -e "  ${GREEN}●${NC} Info    ${YELLOW}●${NC} Warning    ${RED}●${NC} Error"
echo -e "  ${CYAN}●${NC} Performance    ${MAGENTA}●${NC} Memory"
echo ""
echo "================================================"
echo ""

# Function to colorize logs
colorize_log() {
    while IFS= read -r line; do
        if echo "$line" | grep -q "ERROR\|FATAL\|crash"; then
            echo -e "${RED}● $line${NC}"
        elif echo "$line" | grep -q "WARNING\|WARN\|slow"; then
            echo -e "${YELLOW}● $line${NC}"
        elif echo "$line" | grep -q "PERF\|FPS\|Processing:"; then
            echo -e "${CYAN}● $line${NC}"
        elif echo "$line" | grep -q "Memory\|MB\|alloc"; then
            echo -e "${MAGENTA}● $line${NC}"
        elif echo "$line" | grep -q "✅\|SUCCESS\|complete"; then
            echo -e "${GREEN}● $line${NC}"
        else
            echo "  $line"
        fi
    done
}

# Monitor using log stream
log stream \
    --device \
    --predicate 'subsystem == "com.yingif.rgb2gif2voxel" OR processImagePath ENDSWITH "RGB2GIF2VOXEL"' \
    --style compact \
    --color always \
    | grep -E "Performance|Frame|Memory|FPS|Processing|ERROR|WARNING|✅|capture|GIF" \
    | colorize_log