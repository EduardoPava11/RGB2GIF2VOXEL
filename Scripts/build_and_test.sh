#!/bin/bash

# Build and test script - measures ACTUAL performance, no BS

echo "🔨 RGB2GIF2VOXEL Build & Benchmark"
echo "=================================="
echo ""

# 1. Build minimal Rust library
echo "📦 Building Rust library..."
cd rust-minimal
cargo build --release --target aarch64-apple-ios 2>&1 | grep -E "Compiling|Finished|error"
if [ $? -ne 0 ]; then
    echo "❌ Rust build failed"
    exit 1
fi
cd ..

# 2. Copy library to expected location
echo "📋 Copying library..."
mkdir -p RGB2GIF2VOXEL/Frameworks
cp rust-minimal/target/aarch64-apple-ios/release/librust_minimal.a RGB2GIF2VOXEL/Frameworks/

# 3. Fix iOS deployment target
echo "🔧 Fixing deployment target..."
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 26.0/IPHONEOS_DEPLOYMENT_TARGET = 17.0/g' RGB2GIF2VOXEL.xcodeproj/project.pbxproj

# 4. Build Xcode project
echo "🏗️ Building Xcode project..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
           -scheme RGB2GIF2VOXEL \
           -sdk iphonesimulator \
           -configuration Debug \
           build 2>&1 | grep -E "BUILD|error:|warning:"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Xcode build failed"
    echo "Running detailed error check..."
    xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
               -scheme RGB2GIF2VOXEL \
               -sdk iphonesimulator \
               -configuration Debug \
               build 2>&1 | grep -B2 -A2 "error:"
    exit 1
fi

# 5. Run benchmarks
echo ""
echo "🏃 Running benchmarks..."
xcodebuild test \
           -project RGB2GIF2VOXEL.xcodeproj \
           -scheme RGB2GIF2VOXEL \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -only-testing:RGB2GIF2VOXELTests/RealisticBenchmarks \
           2>&1 | grep -E "Test|ms|Speedup|📊"

echo ""
echo "✅ Build and benchmark complete!"
echo ""
echo "📊 Performance Summary:"
echo "----------------------"

# Extract key metrics from test output
echo "Stock Swift baseline: Check test output above"
echo "Optimized pipeline: Check test output above"
echo "ACTUAL speedup: Check test output above"
echo ""
echo "⚠️ These are REAL measurements, not theoretical claims"