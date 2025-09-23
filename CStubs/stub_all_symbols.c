// Complete stubs for all Rust FFI symbols
#include <stdint.h>
#include <stddef.h>

// rgb2gif_processor function symbols
void uniffi_rgb2gif_processor_fn_init_callback_vtable() {}
void uniffi_rgb2gif_processor_fn_func_process_all_frames() {}
void uniffi_rgb2gif_processor_fn_func_calculate_buffer_size() {}
void uniffi_rgb2gif_processor_fn_func_validate_buffer() {}

// rgb2gif_processor checksum symbols
uint16_t uniffi_rgb2gif_processor_checksum_func_process_all_frames() { return 0; }
uint16_t uniffi_rgb2gif_processor_checksum_func_calculate_buffer_size() { return 0; }
uint16_t uniffi_rgb2gif_processor_checksum_func_validate_buffer() { return 0; }
uint16_t uniffi_rgb2gif_processor_checksum_method_processresult_processing_time_ms() { return 0; }

// rust future symbols
void rgb2gif_processor_rust_future_poll() {}
void rgb2gif_processor_rust_future_complete() {}
void rgb2gif_processor_rust_future_cancel() {}
void rgb2gif_processor_rust_future_free() {}

// rust buffer symbols
void ffi_rgb2gif_processor_rustbuffer_alloc() {}
void ffi_rgb2gif_processor_rustbuffer_from_bytes() {}
void ffi_rgb2gif_processor_rustbuffer_free() {}
void ffi_rgb2gif_processor_rustbuffer_reserve() {}

// yingif processor symbols
void yingif_processor_stub() {}
void uniffi_yingif_processor_fn_func_process_frame() {}
void uniffi_yingif_processor_checksum_func_process_frame() {}
void* yingif_processor_new() { return (void*)1; }
void yingif_processor_free(void* p) {}
int32_t yingif_process_frame(const void* data, size_t len, void* out, size_t out_len) { return 0; }
size_t yingif_estimate_gif_size(int w, int h, int frames) { return w * h * frames; }
int32_t yingif_create_gif89a(const void* data, size_t len, void* out, size_t out_len) { return 0; }

// rust minimal symbols
void rust_minimal_stub() {}

// Additional symbols that might be needed
void uniffi_rgb2gif_processor_checksum_method_processresult_gif_data() {}
void uniffi_rgb2gif_processor_checksum_method_processresult_palette_size_used() {}
void uniffi_rgb2gif_processor_checksum_method_processresult_tensor_data() {}

// Contract version symbol
uint32_t ffi_rgb2gif_processor_uniffi_contract_version() { return 0x00000025; }