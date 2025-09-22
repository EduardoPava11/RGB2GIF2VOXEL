#!/bin/bash
# Monitor RGB2GIF2VOXEL app stability

echo "================================================"
echo "📱 MONITORING RGB2GIF2VOXEL STABILITY"
echo "================================================"
echo ""

# Start log streaming
echo "Starting log monitor (press Ctrl+C to stop)..."
echo ""

xcrun devicectl device process streamlog \
    --device 00008150-00113DCA0280401C \
    --process YIN.RGB2GIF2VOXEL 2>&1 | while read -r line; do

    # Highlight important messages
    if echo "$line" | grep -q -E "crash|error|exception|abort|fault|terminated|FFI|yingif|GIF89a"; then
        echo "🔴 $line"
    elif echo "$line" | grep -q -E "success|complete|created|saved|exported"; then
        echo "✅ $line"
    elif echo "$line" | grep -q -E "memory|warning|pressure"; then
        echo "⚠️ $line"
    elif echo "$line" | grep -q -E "frame|capture|process|quantize"; then
        echo "📸 $line"
    else
        echo "  $line"
    fi
done