#!/bin/bash

# Comprehensive Build Verification Script for RGB2GIF2VOXEL
# This script checks for all common Xcode build issues

echo "================================================"
echo "RGB2GIF2VOXEL Xcode Build Verification"
echo "================================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track issues
ISSUES_FOUND=0

# 1. Check Info.plist location and configuration
echo "1. Info.plist Configuration:"
if [ -f "Info.plist" ]; then
    echo -e "   ${GREEN}✅ Info.plist found at project root${NC}"
else
    echo -e "   ${RED}❌ Info.plist not found at project root${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check it's not in the synchronized directory
if [ -f "RGB2GIF2VOXEL/Info.plist" ]; then
    echo -e "   ${RED}❌ Info.plist found in synchronized directory (will cause conflicts)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✅ No Info.plist in synchronized directory${NC}"
fi

# Check project settings
if grep -q "GENERATE_INFOPLIST_FILE = NO" RGB2GIF2VOXEL.xcodeproj/project.pbxproj; then
    echo -e "   ${GREEN}✅ GENERATE_INFOPLIST_FILE = NO is set${NC}"
else
    echo -e "   ${RED}❌ GENERATE_INFOPLIST_FILE is not set to NO${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if grep -q "INFOPLIST_FILE = Info.plist" RGB2GIF2VOXEL.xcodeproj/project.pbxproj; then
    echo -e "   ${GREEN}✅ INFOPLIST_FILE correctly points to Info.plist${NC}"
else
    echo -e "   ${YELLOW}⚠️  INFOPLIST_FILE may not be correctly configured${NC}"
fi

echo ""

# 2. Check for duplicate Swift files
echo "2. Swift File Duplicates:"
duplicates=$(find RGB2GIF2VOXEL -name "*.swift" -exec basename {} \; 2>/dev/null | sort | uniq -d)
if [ -z "$duplicates" ]; then
    echo -e "   ${GREEN}✅ No duplicate Swift filenames found${NC}"
else
    echo -e "   ${RED}❌ Duplicate Swift filenames found:${NC}"
    echo "$duplicates"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""

# 3. Check for backup files
echo "3. Backup Files:"
backups=$(find RGB2GIF2VOXEL -name "*.backup" -o -name "*.swift.backup" -o -name "*~" 2>/dev/null)
if [ -z "$backups" ]; then
    echo -e "   ${GREEN}✅ No backup files found in source directory${NC}"
else
    echo -e "   ${YELLOW}⚠️  Backup files found (ensure no target membership):${NC}"
    echo "$backups"
fi

echo ""

# 4. Check for required directories
echo "4. Project Structure:"
required_dirs=(
    "RGB2GIF2VOXEL/Camera"
    "RGB2GIF2VOXEL/Views"
    "RGB2GIF2VOXEL/Bridge"
    "RGB2GIF2VOXEL/Models"
    "RGB2GIF2VOXEL/FileFormats"
    "RGB2GIF2VOXEL/Voxel"
)

for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "   ${GREEN}✅ $(basename $dir)/ directory exists${NC}"
    else
        echo -e "   ${YELLOW}⚠️  $(basename $dir)/ directory missing${NC}"
    fi
done

echo ""

# 5. Check critical Swift files
echo "5. Critical Swift Files:"
critical_files=(
    "RGB2GIF2VOXEL/RGB2GIF2VOXELApp.swift"
    "RGB2GIF2VOXEL/ContentView.swift"
    "RGB2GIF2VOXEL/Camera/CubeCameraManager.swift"
    "RGB2GIF2VOXEL/Views/CubeCameraView.swift"
    "RGB2GIF2VOXEL/FileFormats/YXVTypes.swift"
    "RGB2GIF2VOXEL/FileFormats/YXVIO_Simple.swift"
    "RGB2GIF2VOXEL/Voxel/VoxelRenderEngine.swift"
    "RGB2GIF2VOXEL/Voxel/VoxelViewerView.swift"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "   ${GREEN}✅ $(basename $file)${NC}"
    else
        echo -e "   ${YELLOW}⚠️  $(basename $file) not found${NC}"
    fi
done

echo ""

# 6. Check for fileSystemSynchronizedGroups
echo "6. File System Synchronization:"
if grep -q "fileSystemSynchronizedGroups" RGB2GIF2VOXEL.xcodeproj/project.pbxproj; then
    echo -e "   ${GREEN}✅ Using fileSystemSynchronizedGroups (Xcode 17 feature)${NC}"
    echo -e "   ${YELLOW}⚠️  Ensure Info.plist is excluded from synchronized group${NC}"
else
    echo -e "   Using manual file references"
fi

echo ""

# 7. Check Resources Build Phase
echo "7. Resources Build Phase:"
resources=$(grep -A 5 "isa = PBXResourcesBuildPhase" RGB2GIF2VOXEL.xcodeproj/project.pbxproj | grep -c "files = (")
if [ "$resources" -gt 0 ]; then
    # Check if Info.plist is in resources
    if grep -A 20 "isa = PBXResourcesBuildPhase" RGB2GIF2VOXEL.xcodeproj/project.pbxproj | grep -q "Info.plist"; then
        echo -e "   ${RED}❌ Info.plist found in Copy Bundle Resources (remove it!)${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "   ${GREEN}✅ Info.plist not in Copy Bundle Resources${NC}"
    fi
else
    echo -e "   ${GREEN}✅ Resources phase appears empty or clean${NC}"
fi

echo ""

# Summary
echo "================================================"
echo "Verification Summary"
echo "================================================"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Project should build without Info.plist conflicts.${NC}"
else
    echo -e "${RED}❌ Found $ISSUES_FOUND issue(s) that need fixing.${NC}"
    echo ""
    echo "To fix Info.plist issues:"
    echo "1. Ensure Info.plist is at project root (not in RGB2GIF2VOXEL/)"
    echo "2. In Xcode, select Info.plist and uncheck target membership"
    echo "3. Clean Build Folder (Shift+Cmd+K)"
    echo "4. Build again (Cmd+B)"
fi

echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Clean Build Folder: Product → Clean Build Folder"
echo "3. Build: Product → Build (Cmd+B)"
echo "4. If errors persist, check Report Navigator for details"

# Exit with error code if issues found
exit $ISSUES_FOUND