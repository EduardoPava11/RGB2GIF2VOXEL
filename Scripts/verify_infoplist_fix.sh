#!/bin/bash

echo "=========================================="
echo "Info.plist Configuration Verification"
echo "=========================================="
echo ""

# Check for duplicate Info.plist files
echo "Checking for Info.plist files..."
INFO_FILES=$(find . -name "Info.plist" -not -path "*/xcframework/*" -not -path "*/Build/*" -not -path "*/DerivedData/*" -type f)
INFO_COUNT=$(echo "$INFO_FILES" | grep -c .)

if [ "$INFO_COUNT" -eq 1 ]; then
    echo "✅ Single Info.plist found (correct):"
    echo "   $INFO_FILES"
else
    echo "❌ Multiple Info.plist files found:"
    echo "$INFO_FILES" | sed 's/^/   /'
fi

echo ""
echo "Checking Xcode project settings..."

# Check GENERATE_INFOPLIST_FILE setting
GENERATE_SETTING=$(grep "GENERATE_INFOPLIST_FILE" RGB2GIF2VOXEL.xcodeproj/project.pbxproj | head -1)
if echo "$GENERATE_SETTING" | grep -q "NO"; then
    echo "✅ GENERATE_INFOPLIST_FILE = NO (correct)"
else
    echo "❌ GENERATE_INFOPLIST_FILE is not set to NO"
    echo "   Found: $GENERATE_SETTING"
fi

# Check INFOPLIST_FILE setting
INFOPLIST_SETTING=$(grep "INFOPLIST_FILE" RGB2GIF2VOXEL.xcodeproj/project.pbxproj | head -1)
if echo "$INFOPLIST_SETTING" | grep -q "RGB2GIF2VOXEL/Info.plist"; then
    echo "✅ INFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist (correct)"
else
    echo "❌ INFOPLIST_FILE is not correctly set"
    echo "   Found: $INFOPLIST_SETTING"
fi

echo ""
echo "Checking Info.plist contents..."
INFO_PATH="RGB2GIF2VOXEL/Info.plist"

if [ -f "$INFO_PATH" ]; then
    # Check for required keys
    REQUIRED_KEYS=("CFBundleExecutable" "CFBundleIdentifier" "NSCameraUsageDescription" "NSPhotoLibraryAddUsageDescription")
    MISSING_KEYS=0
    
    for key in "${REQUIRED_KEYS[@]}"; do
        if grep -q "$key" "$INFO_PATH"; then
            echo "✅ $key present"
        else
            echo "❌ $key missing"
            ((MISSING_KEYS++))
        fi
    done
    
    if [ "$MISSING_KEYS" -eq 0 ]; then
        echo "
✅ All required keys present"
    else
        echo "
❌ $MISSING_KEYS required keys missing"
    fi
else
    echo "❌ Info.plist file not found at $INFO_PATH"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "To build the project:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Product → Clean Build Folder (Shift+Cmd+K)"
echo "3. Product → Build (Cmd+B)"
echo ""
echo "If you still see 'Multiple commands produce Info.plist':"
echo "- Delete DerivedData:"
echo "  rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*"
echo "- In Xcode, check Build Phases → Copy Bundle Resources"
echo "  and ensure Info.plist is NOT listed there"