#!/bin/bash

# Fix Info.plist conflict in Xcode project
# This script updates the project.pbxproj to resolve "Multiple commands produce Info.plist" error

echo "=========================================="
echo "Fixing Info.plist Conflict in Xcode Project"
echo "=========================================="
echo ""

PROJECT_FILE="RGB2GIF2VOXEL.xcodeproj/project.pbxproj"

# Backup the project file
cp "$PROJECT_FILE" "${PROJECT_FILE}.backup"
echo "✅ Created backup: ${PROJECT_FILE}.backup"

# Fix 1: Set GENERATE_INFOPLIST_FILE = NO since we have our own Info.plist
echo "Fixing GENERATE_INFOPLIST_FILE setting..."
sed -i '' 's/GENERATE_INFOPLIST_FILE = YES;/GENERATE_INFOPLIST_FILE = NO;/' "$PROJECT_FILE"

# Fix 2: Add explicit INFOPLIST_FILE path if not present
echo "Setting explicit INFOPLIST_FILE path..."
if ! grep -q "INFOPLIST_FILE" "$PROJECT_FILE"; then
    # Add INFOPLIST_FILE setting after GENERATE_INFOPLIST_FILE
    sed -i '' '/GENERATE_INFOPLIST_FILE = NO;/a\
\t\t\t\tINFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist;' "$PROJECT_FILE"
else
    # Update existing INFOPLIST_FILE to correct path
    sed -i '' 's|INFOPLIST_FILE = .*|INFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist;|' "$PROJECT_FILE"
fi

echo ""
echo "Changes made:"
echo "1. ❌ GENERATE_INFOPLIST_FILE = NO (was YES)"
echo "2. ✅ INFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist"
echo ""

# Verify only one Info.plist exists
echo "Verifying Info.plist files..."
INFO_COUNT=$(find . -name "Info.plist" -not -path "*/xcframework/*" -not -path "*/Build/*" -type f | wc -l)
if [ "$INFO_COUNT" -eq 1 ]; then
    echo "✅ Only one Info.plist file found (correct)"
    find . -name "Info.plist" -not -path "*/xcframework/*" -not -path "*/Build/*" -type f
else
    echo "⚠️  Multiple Info.plist files found:"
    find . -name "Info.plist" -not -path "*/xcframework/*" -not -path "*/Build/*" -type f
fi

echo ""
echo "=========================================="
echo "✅ Fix Applied Successfully"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Clean Build Folder (Product → Clean Build Folder)"
echo "3. Build the project"
echo ""
echo "If issues persist:"
echo "- Delete DerivedData: rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*"
echo "- Restore backup if needed: mv ${PROJECT_FILE}.backup $PROJECT_FILE"