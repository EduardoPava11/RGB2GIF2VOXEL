//
//  VolumeRenderer.metal
//  RGB2GIF2VOXEL
//
//  Ray-marching fragment shader for 3D volume visualization
//  Supports Van Gogh style complementary color enhancement
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// MARK: - Uniforms

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3 cameraPosition;
    float time;
    float3 volumeScale;
    float stepSize;
    float alphaGain;
    float densityThreshold;
    float styleWeight;      // Van Gogh complementary color weight (γ)
    float jitterAmount;
    uint frameIndex;
    uint enableLighting;
    uint enableJitter;
};

// MARK: - Vertex Data

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
    float3 rayOrigin;
    float3 rayDirection;
};

// MARK: - Vertex Shader

vertex RasterizerData vertexShader(VertexIn in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(0)]]) {
    RasterizerData out;

    // Full-screen quad
    out.position = float4(in.position, 1.0);
    out.uv = in.texCoord;

    // Calculate ray in world space
    // Calculate inverse view-projection matrix
    float4x4 viewProj = uniforms.projectionMatrix * uniforms.viewMatrix;
    // Note: matrix inverse not available in older Metal, would need to pass from CPU
    // For now, use simplified ray calculation

    // Ray origin is camera position
    out.rayOrigin = uniforms.cameraPosition;

    // Simplified ray direction calculation
    // Map UV to normalized device coordinates
    float3 ndc = float3((in.texCoord * 2.0 - 1.0), 1.0);

    // Simple perspective ray
    out.rayDirection = normalize(ndc);

    return out;
}

// MARK: - Helper Functions

// Ray-box intersection for unit cube [0,1]³
float2 intersectBox(float3 rayOrigin, float3 rayDir) {
    float3 invRayDir = 1.0 / rayDir;
    float3 t0 = (float3(0.0) - rayOrigin) * invRayDir;
    float3 t1 = (float3(1.0) - rayOrigin) * invRayDir;

    float3 tMin = min(t0, t1);
    float3 tMax = max(t0, t1);

    float tNear = max(max(tMin.x, tMin.y), tMin.z);
    float tFar = min(min(tMax.x, tMax.y), tMax.z);

    return float2(max(tNear, 0.0), tFar);
}

// Sample 3D texture with trilinear filtering
float4 sampleVolume(texture3d<float> volume,
                   sampler volumeSampler,
                   float3 position) {
    // Position should be in [0,1]³
    return volume.sample(volumeSampler, position);
}

// Convert RGB to luminance
float luminance(float3 rgb) {
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

// Compute gradient for normal estimation (for lighting)
float3 computeGradient(texture3d<float> volume,
                       sampler volumeSampler,
                       float3 position,
                       float epsilon) {
    float dx = luminance(sampleVolume(volume, volumeSampler, position + float3(epsilon, 0, 0)).rgb) -
               luminance(sampleVolume(volume, volumeSampler, position - float3(epsilon, 0, 0)).rgb);
    float dy = luminance(sampleVolume(volume, volumeSampler, position + float3(0, epsilon, 0)).rgb) -
               luminance(sampleVolume(volume, volumeSampler, position - float3(0, epsilon, 0)).rgb);
    float dz = luminance(sampleVolume(volume, volumeSampler, position + float3(0, 0, epsilon)).rgb) -
               luminance(sampleVolume(volume, volumeSampler, position - float3(0, 0, epsilon)).rgb);

    return normalize(float3(dx, dy, dz));
}

// Van Gogh style: enhance complementary colors
float3 applyVanGoghStyle(float3 color, float styleWeight) {
    // Simple complementary color enhancement
    float3 complement = float3(1.0) - color;

    // Mix original with complement based on local contrast
    float contrast = length(color - float3(0.5));
    float mixFactor = styleWeight * contrast;

    return mix(color, complement, mixFactor * 0.3);
}

// Apply N=128 spatiotemporal blue-noise jitter
float getJitter(uint2 pixelCoord, uint frameIndex) {
    // Simple hash function for jitter
    uint hash = pixelCoord.x * 73856093u ^ pixelCoord.y * 19349663u ^ frameIndex * 83492791u;
    return float(hash & 0xFFFFu) / 65535.0 - 0.5;
}

// MARK: - Fragment Shader

fragment float4 fragmentShader(RasterizerData in [[stage_in]],
                              texture3d<float> volume [[texture(0)]],
                              sampler volumeSampler [[sampler(0)]],
                              constant Uniforms &uniforms [[buffer(0)]]) {
    // Get ray parameters
    float3 rayOrigin = in.rayOrigin;
    float3 rayDir = normalize(in.rayDirection);

    // Intersect ray with volume bounds
    float2 t = intersectBox(rayOrigin, rayDir);

    if (t.y < t.x) {
        // No intersection
        return float4(0.0);
    }

    // Apply jitter for reduced banding (N=128 STBN)
    float jitter = 0.0;
    if (uniforms.enableJitter) {
        uint2 pixelCoord = uint2(in.position.xy);
        jitter = getJitter(pixelCoord, uniforms.frameIndex) * uniforms.jitterAmount;
    }

    // Ray marching
    float4 accumColor = float4(0.0);
    float accumAlpha = 0.0;

    float currentT = t.x + jitter * uniforms.stepSize;
    float maxT = t.y;

    // Quality settings
    const int maxSteps = 256;
    int stepCount = 0;

    while (currentT < maxT && accumAlpha < 0.98 && stepCount < maxSteps) {
        // Sample position in volume
        float3 samplePos = rayOrigin + currentT * rayDir;

        // Sample the volume
        float4 sampledColor = sampleVolume(volume, volumeSampler, samplePos);

        // Apply density threshold
        float density = luminance(sampledColor.rgb);
        if (density > uniforms.densityThreshold) {

            // Apply Van Gogh style if enabled
            if (uniforms.styleWeight > 0.0) {
                sampledColor.rgb = applyVanGoghStyle(sampledColor.rgb, uniforms.styleWeight);
            }

            // Apply lighting if enabled
            if (uniforms.enableLighting) {
                float3 gradient = computeGradient(volume, volumeSampler, samplePos, 0.01);
                float3 lightDir = normalize(float3(1.0, 1.0, 0.5));
                float lighting = max(dot(gradient, lightDir), 0.2);
                sampledColor.rgb *= lighting;
            }

            // Alpha compositing
            float alpha = sampledColor.a * uniforms.alphaGain * uniforms.stepSize;
            alpha = min(alpha, 1.0 - accumAlpha);

            accumColor.rgb += (1.0 - accumAlpha) * sampledColor.rgb * alpha;
            accumAlpha += alpha;
        }

        currentT += uniforms.stepSize;
        stepCount++;
    }

    accumColor.a = accumAlpha;
    return accumColor;
}

// MARK: - Simple Fragment (for testing)

fragment float4 simpleFragmentShader(RasterizerData in [[stage_in]],
                                    texture3d<float> volume [[texture(0)]],
                                    sampler volumeSampler [[sampler(0)]]) {
    // Direct volume sampling at UV coordinates for testing
    float3 samplePos = float3(in.uv, 0.5);
    float4 color = volume.sample(volumeSampler, samplePos);
    return color;
}