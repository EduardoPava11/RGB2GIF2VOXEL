#!/bin/bash
# Setup script for YXV (YinVoxel) format implementation

set -e

echo "========================================="
echo "YXV Format Setup Script"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Install FlatBuffers compiler if not installed
echo "1. Checking for flatc (FlatBuffers compiler)..."
if ! command -v flatc &> /dev/null; then
    echo -e "${YELLOW}flatc not found. Installing via Homebrew...${NC}"
    brew install flatbuffers
else
    echo -e "${GREEN}✓ flatc found: $(flatc --version)${NC}"
fi

# Step 2: Generate Swift code from FlatBuffers schema
echo ""
echo "2. Generating Swift code from FlatBuffers schema..."
mkdir -p RGB2GIF2VOXEL/Generated
flatc --swift -o RGB2GIF2VOXEL/Generated schemas/yinvxl.fbs
echo -e "${GREEN}✓ Swift code generated${NC}"

# Step 3: Generate Rust code from FlatBuffers schema
echo ""
echo "3. Generating Rust code from FlatBuffers schema..."
mkdir -p yinvxl-rs/src/schemas
flatc --rust -o yinvxl-rs/src/schemas schemas/yinvxl.fbs
echo -e "${GREEN}✓ Rust code generated${NC}"

# Step 4: Generate C++ headers for Zig
echo ""
echo "4. Generating C++ headers for Zig..."
mkdir -p zig-yxv/flatbuffers
flatc --cpp -o zig-yxv/flatbuffers schemas/yinvxl.fbs
echo -e "${GREEN}✓ C++ headers generated${NC}"

# Step 5: Add FlatBuffers Swift package to Xcode project
echo ""
echo "5. Next steps for Xcode integration:"
echo "   a) Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "   b) File → Add Package Dependencies"
echo "   c) Enter URL: https://github.com/microsoft/flatbuffers"
echo "   d) Add FlatBuffers product to your app target"
echo "   e) Add these files to your target:"
echo "      - RGB2GIF2VOXEL/FileFormats/YXVTypes.swift"
echo "      - RGB2GIF2VOXEL/FileFormats/YXVIO.swift"
echo "      - RGB2GIF2VOXEL/Generated/yinvxl_generated.swift"

# Step 6: Build Rust library (optional)
echo ""
echo "6. Building Rust YXV library..."
cd yinvxl-rs
if cargo build --release 2>/dev/null; then
    echo -e "${GREEN}✓ Rust library built successfully${NC}"
else
    echo -e "${YELLOW}⚠ Rust build failed (missing dependencies?)${NC}"
    echo "   Run: cd yinvxl-rs && cargo build --release"
fi
cd ..

# Step 7: Create sample YXV export button integration
echo ""
echo "7. To add YXV export to your app:"
cat << 'EOF'

Add to CubeCameraView.swift:

    Button("Export YXV") {
        Task {
            if let yxvURL = await coordinator.exportYXV(tensor: coordinator.cubeTensor) {
                print("YXV exported to: \(yxvURL)")
                // Show share sheet or success message
            }
        }
    }
    .buttonStyle(.borderedProminent)
    .disabled(!coordinator.canExportGIF)

EOF

echo ""
echo "========================================="
echo -e "${GREEN}✅ YXV Setup Complete!${NC}"
echo "========================================="
echo ""
echo "Summary of created files:"
echo "  • schemas/yinvxl.fbs - FlatBuffers schema"
echo "  • YXVTypes.swift - Swift types and constants"
echo "  • YXVIO.swift - Swift reader/writer"
echo "  • yinvxl-rs/ - Rust crate for CLI tools"
echo "  • zig-yxv/ - Zig implementation stub"
echo ""
echo "To complete integration:"
echo "  1. Add FlatBuffers Swift package in Xcode"
echo "  2. Add generated files to app target"
echo "  3. Wire export button in UI"
echo "  4. Test with: cargo run --bin yxv -- info <file.yxv>"