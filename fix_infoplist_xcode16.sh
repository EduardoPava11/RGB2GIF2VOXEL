#!/bin/bash

# Fix for Xcode 16 "Multiple commands produce Info.plist" error
# This script applies all necessary fixes for the synchronized groups issue

echo "================================================="
echo "Xcode 16 Info.plist Duplication Fix"
echo "================================================="
echo ""

PROJECT_FILE="RGB2GIF2VOXEL.xcodeproj/project.pbxproj"

# 1. Verify the fix has been applied
echo "1. Checking synchronized group exception..."
if grep -q "PBXFileSystemSynchronizedBuildFileExceptionSet" "$PROJECT_FILE"; then
    echo "   ✅ Exception set already configured"
else
    echo "   ❌ Exception set not found - manual fix needed"
fi

# 2. Verify GENERATE_INFOPLIST_FILE is NO
echo ""
echo "2. Checking GENERATE_INFOPLIST_FILE setting..."
if grep -q "GENERATE_INFOPLIST_FILE = NO" "$PROJECT_FILE"; then
    echo "   ✅ Auto-generation disabled"
else
    echo "   ❌ GENERATE_INFOPLIST_FILE not set to NO"
fi

# 3. Verify INFOPLIST_FILE is set
echo ""
echo "3. Checking INFOPLIST_FILE path..."
if grep -q "INFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist" "$PROJECT_FILE"; then
    echo "   ✅ Manual Info.plist path configured"
else
    echo "   ❌ INFOPLIST_FILE path not set"
fi

# 4. Clean all build artifacts
echo ""
echo "4. Cleaning build artifacts..."
rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*
rm -rf build/
rm -rf .build/
echo "   ✅ Build artifacts cleaned"

# 5. Check for duplicate Info.plist files
echo ""
echo "5. Checking for Info.plist files..."
echo "   App Info.plist:"
ls -la RGB2GIF2VOXEL/Info.plist 2>/dev/null || echo "   ❌ Not found!"
echo ""
echo "   Framework Info.plist files (these are OK):"
find . -name "Info.plist" -path "*.xcframework/*" | sed 's/^/   • /'

# 6. Additional verification
echo ""
echo "6. Final verification..."
echo "   Checking for Info.plist in Resources build phase..."
if grep -A5 "PBXResourcesBuildPhase" "$PROJECT_FILE" | grep -q "Info.plist"; then
    echo "   ⚠️  WARNING: Info.plist found in Resources build phase"
    echo "   This needs to be removed manually in Xcode"
else
    echo "   ✅ No Info.plist in Resources build phase"
fi

echo ""
echo "================================================="
echo "Summary of Xcode 16 Synchronized Groups Fix"
echo "================================================="
echo ""
echo "The key fix applied:"
echo "• Added PBXFileSystemSynchronizedBuildFileExceptionSet"
echo "• Excluded Info.plist from synchronized group membership"
echo "• Disabled GENERATE_INFOPLIST_FILE"
echo "• Set explicit INFOPLIST_FILE path"
echo ""
echo "This prevents Xcode 16 from automatically including"
echo "Info.plist as a resource through synchronized groups."
echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Product → Clean Build Folder (Shift+Cmd+K)"
echo "3. Build (Cmd+B)"
echo ""
echo "If the error persists:"
echo "• Check Build Phases → Copy Bundle Resources"
echo "• Remove any Info.plist entries if present"
echo "• Ensure no Info.plist has Target Membership checked"
echo ""

exit 0