// Build script for UniFFI code generation

fn main() {
    uniffi::generate_scaffolding("src/rgb2gif.udl").unwrap();
}