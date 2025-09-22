#!/bin/bash
# disable_previews.sh - Wrap all #Preview blocks to prevent compilation

echo "🔧 Disabling SwiftUI Previews in code..."

# Find all Swift files with #Preview
find RGB2GIF2VOXEL -name "*.swift" -type f | while read file; do
    if grep -q "#Preview" "$file"; then
        echo "   Updating: $(basename $file)"

        # Wrap #Preview blocks with conditional compilation
        perl -i -pe 's/^#Preview\b/#if DEBUG && ENABLE_PREVIEWS\n#Preview/g' "$file"
        perl -i -pe 's/^(#Preview \{[\s\S]*?\n\})/$1\n#endif/g' "$file"
    fi
done

echo "✅ Preview blocks wrapped with conditional compilation"
echo ""
echo "To re-enable previews later:"
echo "1. Add ENABLE_PREVIEWS to Active Compilation Conditions"
echo "2. Build simulator slices of native libraries"