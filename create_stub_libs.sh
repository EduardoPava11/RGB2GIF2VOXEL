#!/bin/bash
# Create stub libraries for simulator build

cd /Users/daniel/Documents/RGB2GIF2VOXEL/RGB2GIF2VOXEL/Frameworks

# Create empty C files with the required symbols
cat > stub_yingif.c << 'EOF'
// Stub for yingif_processor library
void yingif_processor_stub() {}
EOF

cat > stub_rgb2gif.c << 'EOF'
// Stub for rgb2gif_processor library
void uniffi_rgb2gif_processor_fn_init_callback_vtable() {}
void uniffi_rgb2gif_processor_fn_func_process_all_frames() {}
void rgb2gif_processor_rust_future_poll() {}
void rgb2gif_processor_rust_future_complete() {}
void rgb2gif_processor_rust_future_cancel() {}
void rgb2gif_processor_rust_future_free() {}
EOF

cat > stub_rust_minimal.c << 'EOF'
// Stub for rust_minimal library
void rust_minimal_stub() {}
EOF

# Compile to object files for simulator
clang -c stub_yingif.c -o stub_yingif.o -arch arm64 -target arm64-apple-ios16.0-simulator
clang -c stub_rgb2gif.c -o stub_rgb2gif.o -arch arm64 -target arm64-apple-ios16.0-simulator
clang -c stub_rust_minimal.c -o stub_rust_minimal.o -arch arm64 -target arm64-apple-ios16.0-simulator

# Create static libraries
ar rcs libyingif_processor.a stub_yingif.o
ar rcs librgb2gif_processor.a stub_rgb2gif.o
ar rcs librust_minimal.a stub_rust_minimal.o

# Clean up temp files
rm -f stub_*.c stub_*.o

echo "Created stub libraries for simulator build"