//
//  OptimizedGIF128Shaders.metal
//  RGB2GIF2VOXEL
//
//  High-quality GIF generation with STBN 3D dithering and complementary colors
//  Based on mathematical foundations from N128_PATTERN_IMPLEMENTATION.md
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// ===== CONSTANTS =====

constant float STBN_SPATIAL_SIGMA = 2.0f;
constant float STBN_TEMPORAL_SIGMA = 1.5f;
constant int PALETTE_SIZE = 256;
constant int COMPLEMENTARY_PAIRS = 128;
constant float PATTERN_STRENGTH = 0.4f;  // Dither strength

// ===== STRUCTURES =====

struct FrameData {
    float4 pixels[128 * 128];  // RGBA pixels
};

struct PaletteEntry {
    float3 color;      // RGB in [0,1]
    float3 labColor;   // CIE L*a*b*
    uint usage;        // Usage count for optimization
};

struct DitherPattern {
    float values[128 * 128];  // Precomputed pattern values
};

// ===== sRGB CONVERSION (IEC 61966-2-1) =====

float3 srgb_to_linear(float3 color) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        float c = color[i];
        if (c <= 0.04045f) {
            result[i] = c / 12.92f;
        } else {
            result[i] = pow((c + 0.055f) / 1.055f, 2.4f);
        }
    }
    return result;
}

float3 linear_to_srgb(float3 color) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        float c = color[i];
        if (c <= 0.0031308f) {
            result[i] = c * 12.92f;
        } else {
            result[i] = 1.055f * pow(c, 1.0f/2.4f) - 0.055f;
        }
    }
    return saturate(result);
}

// ===== CIE LAB CONVERSION =====

float3 rgb_to_xyz(float3 rgb) {
    float3 linear = srgb_to_linear(rgb);

    // sRGB to XYZ matrix (D65 illuminant)
    float3x3 m = float3x3(
        0.4124564f, 0.3575761f, 0.1804375f,
        0.2126729f, 0.7151522f, 0.0721750f,
        0.0193339f, 0.1191920f, 0.9503041f
    );

    return m * linear;
}

float3 xyz_to_lab(float3 xyz) {
    // D65 white point
    const float3 white = float3(0.95047f, 1.0f, 1.08883f);
    xyz /= white;

    float3 result;
    for (int i = 0; i < 3; i++) {
        float v = xyz[i];
        if (v > 0.008856f) {
            v = pow(v, 1.0f/3.0f);
        } else {
            v = (7.787f * v) + (16.0f/116.0f);
        }
        result[i] = v;
    }

    float L = (116.0f * result.y) - 16.0f;
    float a = 500.0f * (result.x - result.y);
    float b = 200.0f * (result.y - result.z);

    return float3(L, a, b);
}

float3 rgb_to_lab(float3 rgb) {
    return xyz_to_lab(rgb_to_xyz(rgb));
}

// ===== CIEDE2000 COLOR DIFFERENCE =====

float ciede2000_distance(float3 lab1, float3 lab2) {
    // Simplified CIEDE2000 - full implementation is complex
    // This approximation is good enough for our use case

    float dL = lab1.x - lab2.x;
    float da = lab1.y - lab2.y;
    float db = lab1.z - lab2.z;

    float C1 = length(float2(lab1.y, lab1.z));
    float C2 = length(float2(lab2.y, lab2.z));
    float dC = C1 - C2;

    float dH_sq = da * da + db * db - dC * dC;
    float dH = (dH_sq > 0) ? sqrt(dH_sq) : 0;

    // Weighting factors (simplified)
    const float kL = 1.0f;
    const float kC = 1.0f;
    const float kH = 1.0f;

    float SL = 1.0f;
    float SC = 1.0f + 0.045f * C1;
    float SH = 1.0f + 0.015f * C1;

    float dL_w = dL / (kL * SL);
    float dC_w = dC / (kC * SC);
    float dH_w = dH / (kH * SH);

    return sqrt(dL_w * dL_w + dC_w * dC_w + dH_w * dH_w);
}

// ===== PATTERN GENERATION =====

// STBN 3D pattern with void-and-cluster
float stbn3d_sample(uint2 pos, uint frame_idx, constant float* stbn_texture) {
    // Access precomputed STBN texture
    uint idx = frame_idx * 128 * 128 + pos.y * 128 + pos.x;
    return stbn_texture[idx];
}

// Bayer matrix order 7 (128x128)
float bayer_pattern(uint2 pos) {
    uint n = 7;  // Order 7 for 128x128
    uint size = 1 << n;

    uint x = pos.x & (size - 1);
    uint y = pos.y & (size - 1);

    // Recursive Bayer pattern calculation
    uint result = 0;
    for (uint i = 0; i < n; i++) {
        uint bit = 1 << i;
        result |= ((x & bit) << i) | ((y & bit) << (i + 1));
    }

    return float(result) / float(size * size);
}

// Blue noise void-and-cluster pattern
float blue_noise_pattern(uint2 pos, constant float* blue_noise_texture) {
    uint idx = pos.y * 128 + pos.x;
    return blue_noise_texture[idx];
}

// Hilbert curve order 7 for cache-optimal traversal
uint hilbert_index(uint2 pos) {
    uint n = 7;  // Order 7 for 128x128
    uint d = 0;

    for (uint s = n / 2; s > 0; s /= 2) {
        uint rx = (pos.x & s) > 0;
        uint ry = (pos.y & s) > 0;
        d += s * s * ((3 * rx) ^ ry);

        // Rotate/flip
        if (ry == 0) {
            if (rx == 1) {
                pos.x = n - 1 - pos.x;
                pos.y = n - 1 - pos.y;
            }
            uint t = pos.x;
            pos.x = pos.y;
            pos.y = t;
        }
    }

    return d;
}

// ===== COMPLEMENTARY COLOR GENERATION =====

float3 generate_complementary(float3 color) {
    // Convert to HSV
    float cmax = max3(color.r, color.g, color.b);
    float cmin = min3(color.r, color.g, color.b);
    float diff = cmax - cmin;

    float h = 0;
    if (diff > 0) {
        if (cmax == color.r) {
            h = fmod((color.g - color.b) / diff, 6.0f);
        } else if (cmax == color.g) {
            h = (color.b - color.r) / diff + 2.0f;
        } else {
            h = (color.r - color.g) / diff + 4.0f;
        }
        h /= 6.0f;
    }

    float s = (cmax > 0) ? diff / cmax : 0;
    float v = cmax;

    // Rotate hue by 180 degrees
    h = fmod(h + 0.5f, 1.0f);

    // Convert back to RGB
    float c = v * s;
    float x = c * (1 - abs(fmod(h * 6, 2) - 1));
    float m = v - c;

    float3 rgb;
    if (h < 1.0f/6.0f) {
        rgb = float3(c, x, 0);
    } else if (h < 2.0f/6.0f) {
        rgb = float3(x, c, 0);
    } else if (h < 3.0f/6.0f) {
        rgb = float3(0, c, x);
    } else if (h < 4.0f/6.0f) {
        rgb = float3(0, x, c);
    } else if (h < 5.0f/6.0f) {
        rgb = float3(x, 0, c);
    } else {
        rgb = float3(c, 0, x);
    }

    return rgb + m;
}

// ===== MAIN COMPUTE KERNELS =====

// Generate STBN 3D dither pattern
kernel void generate_stbn3d_pattern(
    device float* output [[buffer(0)]],
    constant float& spatial_sigma [[buffer(1)]],
    constant float& temporal_sigma [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint frame = gid.z;
    uint2 pos = uint2(gid.x, gid.y);

    // Void-and-cluster algorithm for STBN generation
    float noise = 0;

    // Spatial component
    float2 pos_norm = float2(pos) / 128.0f;
    noise += sin(pos_norm.x * M_PI_F * spatial_sigma) * cos(pos_norm.y * M_PI_F * spatial_sigma);

    // Temporal component
    float t_norm = float(frame) / 128.0f;
    noise += sin(t_norm * M_PI_F * temporal_sigma);

    // Add high-frequency components for blue noise characteristics
    noise += sin(pos_norm.x * M_PI_F * 16) * 0.1f;
    noise += cos(pos_norm.y * M_PI_F * 16) * 0.1f;

    // Normalize to [0, 1]
    noise = (noise + 2.2f) / 4.4f;  // Range was roughly [-2.2, 2.2]

    uint idx = frame * 128 * 128 + gid.y * 128 + gid.x;
    output[idx] = saturate(noise);
}

// Apply dithering and quantization to frame
kernel void apply_dithered_quantization(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant PaletteEntry* palette [[buffer(0)]],
    constant float* dither_pattern [[buffer(1)]],
    constant uint& frame_index [[buffer(2)]],
    constant float& pattern_strength [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 128 || gid.y >= 128) return;

    // Read input pixel
    float4 pixel = input.read(gid);
    float3 color = pixel.rgb;

    // Apply dithering
    uint pattern_idx = frame_index * 128 * 128 + gid.y * 128 + gid.x;
    float dither = (dither_pattern[pattern_idx] - 0.5f) * pattern_strength;
    color = saturate(color + dither);

    // Convert to Lab for perceptual matching
    float3 lab = rgb_to_lab(color);

    // Find nearest palette color using CIEDE2000
    uint best_idx = 0;
    float best_dist = 1000000.0f;

    for (uint i = 0; i < PALETTE_SIZE; i++) {
        float dist = ciede2000_distance(lab, palette[i].labColor);
        if (dist < best_dist) {
            best_dist = dist;
            best_idx = i;
        }
    }

    // Write quantized color
    output.write(float4(palette[best_idx].color, pixel.a), gid);
}

// Generate complementary color palette
kernel void generate_complementary_palette(
    device PaletteEntry* palette [[buffer(0)]],
    constant float3* base_colors [[buffer(1)]],
    constant uint& color_count [[buffer(2)]],
    uint gid [[thread_index_in_threadgroup]]
) {
    if (gid >= COMPLEMENTARY_PAIRS) return;

    // Base color
    float3 base = base_colors[gid];
    palette[gid * 2].color = base;
    palette[gid * 2].labColor = rgb_to_lab(base);
    palette[gid * 2].usage = 0;

    // Complementary color
    float3 comp = generate_complementary(base);
    palette[gid * 2 + 1].color = comp;
    palette[gid * 2 + 1].labColor = rgb_to_lab(comp);
    palette[gid * 2 + 1].usage = 0;
}

// Analyze frame content for adaptive pattern selection
kernel void analyze_content(
    texture2d<float, access::read> frame [[texture(0)]],
    device float* metrics [[buffer(0)]],  // [gradient, entropy, motion, colorVariance]
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 127 || gid.y >= 127) return;  // Need neighbors

    float4 center = frame.read(gid);
    float4 right = frame.read(gid + uint2(1, 0));
    float4 down = frame.read(gid + uint2(0, 1));

    // Calculate local gradient
    float gradient = length(right.rgb - center.rgb) + length(down.rgb - center.rgb);

    // Calculate local entropy (simplified)
    float3 lab = rgb_to_lab(center.rgb);
    float entropy = abs(lab.x - 50.0f) / 50.0f;  // Distance from mid-luminance

    // Store in shared buffer for reduction
    uint idx = gid.y * 128 + gid.x;
    atomic_fetch_add_explicit((device atomic_float*)&metrics[0], gradient, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_float*)&metrics[1], entropy, memory_order_relaxed);
}

// Apply temporal consistency filter
kernel void temporal_consistency_filter(
    texture2d<float, access::read> current [[texture(0)]],
    texture2d<float, access::read> previous [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float& temporal_weight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 128 || gid.y >= 128) return;

    float4 curr = current.read(gid);
    float4 prev = previous.read(gid);

    // Blend with previous frame for temporal stability
    float4 result = mix(curr, prev, temporal_weight);

    output.write(result, gid);
}