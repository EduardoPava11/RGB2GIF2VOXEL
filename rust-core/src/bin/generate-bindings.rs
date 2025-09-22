use camino::Utf8PathBuf;
use uniffi_bindgen::bindings::SwiftBindingGenerator;

fn main() {
    let udl_file = Utf8PathBuf::from("src/rgb2gif.udl");
    let out_dir = Utf8PathBuf::from("../RGB2GIF2VOXEL/Bridge/Generated");

    // Create output directory if needed
    std::fs::create_dir_all(&out_dir).unwrap();

    // Generate Swift bindings
    uniffi_bindgen::generate_bindings(
        &udl_file,
        None,
        SwiftBindingGenerator,
        Some(&out_dir),
        None,
        None,
        false,
    ).expect("Failed to generate Swift bindings");

    println!("✅ Generated Swift bindings in RGB2GIF2VOXEL/Bridge/Generated");
    println!("   Files generated:");
    println!("   - rgb2gif_processor.swift");
    println!("   - rgb2gif_processorFFI.h");
    println!("   - rgb2gif_processorFFI.modulemap");
}