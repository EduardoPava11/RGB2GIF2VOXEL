#!/bin/bash

# Generate Swift bindings from Rust UniFFI interface
# This script is called from Xcode Build Phases

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_DIR/rust-core"
BRIDGE_DIR="$PROJECT_DIR/RGB2GIF2VOXEL/Bridge"

echo "Generating Swift bindings with UniFFI..."

mkdir -p "$BRIDGE_DIR/Generated"

cd "$SCRIPT_DIR"

# Build and run the binding generator
cargo build --release --quiet
./target/release/uniffi-bindgen generate \
    "$RUST_DIR/src/rgb2gif.udl" \
    --language swift \
    --out-dir "$BRIDGE_DIR/Generated"

echo "Swift bindings generated successfully"

# Create module map for the static library
cat > "$BRIDGE_DIR/Generated/rgb2gif_processorFFI.modulemap" << EOF
module rgb2gif_processorFFI {
    header "rgb2gif_processorFFI.h"
    export *
}
EOF