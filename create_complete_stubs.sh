#!/bin/bash
# Create complete stub libraries with all required symbols for simulator build

cd /Users/daniel/Documents/RGB2GIF2VOXEL/RGB2GIF2VOXEL/Frameworks

# Create C file with ALL required symbols
cat > stub_complete.c << 'EOF'
// Complete stubs for all Rust FFI libraries

// rgb2gif_processor symbols
void uniffi_rgb2gif_processor_fn_init_callback_vtable() {}
void uniffi_rgb2gif_processor_fn_func_process_all_frames() {}
void uniffi_rgb2gif_processor_fn_func_calculate_buffer_size() {}
void uniffi_rgb2gif_processor_fn_func_validate_buffer() {}
void rgb2gif_processor_rust_future_poll() {}
void rgb2gif_processor_rust_future_complete() {}
void rgb2gif_processor_rust_future_cancel() {}
void rgb2gif_processor_rust_future_free() {}
void ffi_rgb2gif_processor_rustbuffer_alloc() {}
void ffi_rgb2gif_processor_rustbuffer_from_bytes() {}
void ffi_rgb2gif_processor_rustbuffer_free() {}
void ffi_rgb2gif_processor_rustbuffer_reserve() {}

// yingif_processor symbols
void yingif_processor_stub() {}
void uniffi_yingif_processor_fn_func_process_frame() {}

// rust_minimal symbols
void rust_minimal_stub() {}
EOF

# Compile for simulator
clang -c stub_complete.c -o stub_rgb2gif.o -arch arm64 -target arm64-apple-ios16.0-simulator
clang -c stub_complete.c -o stub_yingif.o -arch arm64 -target arm64-apple-ios16.0-simulator
clang -c stub_complete.c -o stub_minimal.o -arch arm64 -target arm64-apple-ios16.0-simulator

# Create static libraries
ar rcs librgb2gif_processor.a stub_rgb2gif.o
ar rcs libyingif_processor.a stub_yingif.o
ar rcs librust_minimal.a stub_minimal.o

# Clean up
rm -f stub_*.c stub_*.o

echo "Created complete stub libraries with all symbols"