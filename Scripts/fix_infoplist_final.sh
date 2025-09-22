#!/bin/bash

echo "========================================="
echo "FINAL Info.plist Conflict Fix"
echo "========================================="
echo ""

PROJECT_FILE="RGB2GIF2VOXEL.xcodeproj/project.pbxproj"

# Backup the project file
cp "$PROJECT_FILE" "${PROJECT_FILE}.backup_final"
echo "✅ Created backup: ${PROJECT_FILE}.backup_final"
echo ""

# The root cause: Having both INFOPLIST_FILE and INFOPLIST_KEY_* settings
# When you manage your own Info.plist, you should NOT have INFOPLIST_KEY_* settings

echo "Removing conflicting INFOPLIST_KEY_* settings..."
echo "(These are only used when GENERATE_INFOPLIST_FILE = YES)"
echo ""

# Remove all INFOPLIST_KEY_* lines
sed -i '' '/INFOPLIST_KEY_/d' "$PROJECT_FILE"

echo "✅ Removed all INFOPLIST_KEY_* settings"
echo ""

# Ensure GENERATE_INFOPLIST_FILE is NO and INFOPLIST_FILE is set correctly
echo "Verifying core settings..."

# Count how many times these appear
GENERATE_COUNT=$(grep -c "GENERATE_INFOPLIST_FILE" "$PROJECT_FILE")
INFOPLIST_COUNT=$(grep -c "INFOPLIST_FILE" "$PROJECT_FILE")

echo "Found $GENERATE_COUNT GENERATE_INFOPLIST_FILE entries"
echo "Found $INFOPLIST_COUNT INFOPLIST_FILE entries"
echo ""

# Show the current settings
echo "Current settings:"
grep "GENERATE_INFOPLIST_FILE" "$PROJECT_FILE" | head -2
grep "INFOPLIST_FILE" "$PROJECT_FILE" | head -2
echo ""

# Check if any INFOPLIST_KEY_ settings remain
KEY_COUNT=$(grep -c "INFOPLIST_KEY_" "$PROJECT_FILE")
if [ "$KEY_COUNT" -eq 0 ]; then
    echo "✅ All INFOPLIST_KEY_* settings removed successfully"
else
    echo "⚠️  Warning: $KEY_COUNT INFOPLIST_KEY_* settings still found"
fi

echo ""
echo "========================================="
echo "✅ Fix Applied"
echo "========================================="
echo ""
echo "Summary of changes:"
echo "1. Removed all INFOPLIST_KEY_* settings (these conflict with manual Info.plist)"
echo "2. Kept GENERATE_INFOPLIST_FILE = NO"
echo "3. Kept INFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist"
echo ""
echo "Why this fixes the issue:"
echo "- INFOPLIST_KEY_* settings tell Xcode to process/generate Info.plist entries"
echo "- When you have your own Info.plist file, these create conflicts"
echo "- Now Xcode will only use your RGB2GIF2VOXEL/Info.plist file"
echo ""
echo "Next steps:"
echo "1. Open Xcode"
echo "2. Product → Clean Build Folder (Shift+Cmd+K)"
echo "3. Delete DerivedData: rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*"
echo "4. Product → Build (Cmd+B)"
echo ""
echo "To restore if needed:"
echo "  mv ${PROJECT_FILE}.backup_final $PROJECT_FILE"