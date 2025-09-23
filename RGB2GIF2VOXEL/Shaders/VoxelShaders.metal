//
//  VoxelShaders.metal
//  RGB2GIF2VOXEL
//
//  Metal shaders for voxel cube rendering
//

#include <metal_stdlib>
using namespace metal;

// Vertex data structures
struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texCoord;
    float4 color;
    float depth;
};

// Uniforms structure matching Swift
struct Uniforms {
    float4x4 mvpMatrix;
    float3x3 normalMatrix;
    float3 lightPosition;
    float3 viewPosition;
    float time;
    int frameIndex;
    float2 padding;
};

// Instance data
struct InstanceData {
    float4x4 instanceTransform;
    float4 color;
};

// Vertex shader
vertex VertexOut voxelVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float3* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    constant float4x4* instances [[buffer(2)]]
) {
    VertexOut out;

    // Get vertex position
    float3 vertexPos = vertices[vertexID];

    // Apply instance transform
    float4x4 instanceMatrix = instances[instanceID];
    float4 worldPos = instanceMatrix * float4(vertexPos, 1.0);

    // Apply MVP transform
    out.position = uniforms.mvpMatrix * worldPos;
    out.worldPosition = worldPos.xyz;

    // Calculate normal (for a cube, normals are based on face)
    // Simplified normal calculation for cube faces
    float3 normal = vertexPos;
    if (abs(normal.x) > 0.4) normal = float3(sign(normal.x), 0, 0);
    else if (abs(normal.y) > 0.4) normal = float3(0, sign(normal.y), 0);
    else normal = float3(0, 0, sign(normal.z));

    out.normal = normalize(uniforms.normalMatrix * normal);

    // UV coordinates for texture mapping
    out.texCoord = float2((vertexPos.x + 0.5), (vertexPos.y + 0.5));

    // Voxel color based on position in grid
    float3 gridPos = worldPos.xyz * 128.0;
    out.color = float4(
        sin(gridPos.x * 0.1 + uniforms.time) * 0.5 + 0.5,
        cos(gridPos.y * 0.1 + uniforms.time * 1.3) * 0.5 + 0.5,
        sin(gridPos.z * 0.1 + uniforms.time * 0.7) * 0.5 + 0.5,
        1.0
    );

    out.depth = out.position.z / out.position.w;

    return out;
}

// Fragment shader
fragment float4 voxelFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]],
    texture2d<float> frameTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);

    // Sample frame texture if available
    float4 texColor = frameTexture.sample(texSampler, in.texCoord);

    // Basic lighting
    float3 lightDir = normalize(uniforms.lightPosition - in.worldPosition);
    float3 viewDir = normalize(uniforms.viewPosition - in.worldPosition);
    float3 normal = normalize(in.normal);

    // Diffuse lighting
    float diffuse = max(dot(normal, lightDir), 0.0);

    // Specular lighting
    float3 reflectDir = reflect(-lightDir, normal);
    float specular = pow(max(dot(viewDir, reflectDir), 0.0), 32);

    // Combine lighting with voxel color
    float3 ambient = 0.2 * in.color.rgb;
    float3 diffuseColor = diffuse * in.color.rgb;
    float3 specularColor = specular * float3(1.0);

    // Mix with texture color if available
    float3 finalColor = mix(ambient + diffuseColor + specularColor * 0.5,
                           texColor.rgb,
                           texColor.a);

    // Add depth-based fog for better 3D perception
    float fogFactor = smoothstep(0.8, 1.0, in.depth);
    finalColor = mix(finalColor, float3(0.1, 0.1, 0.15), fogFactor * 0.3);

    // Glass-like effect for voxels
    float fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 2.0);
    finalColor += fresnel * 0.2 * float3(0.6, 0.8, 1.0);

    return float4(finalColor, 0.9);
}

// Alternative shader for wireframe/debug mode
fragment float4 voxelWireframeShader(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    // Edge detection for wireframe effect
    float3 dFdxPos = dfdx(in.worldPosition);
    float3 dFdyPos = dfdy(in.worldPosition);
    float3 normal = normalize(cross(dFdxPos, dFdyPos));

    // Create edge glow
    float edge = 1.0 - abs(dot(normal, normalize(in.normal)));
    edge = smoothstep(0.8, 1.0, edge);

    // Animated color based on position and time
    float3 color = float3(
        sin(in.worldPosition.x * 10.0 + uniforms.time) * 0.5 + 0.5,
        sin(in.worldPosition.y * 10.0 + uniforms.time * 1.5) * 0.5 + 0.5,
        sin(in.worldPosition.z * 10.0 + uniforms.time * 2.0) * 0.5 + 0.5
    );

    return float4(color * (1.0 + edge * 2.0), 0.8 + edge * 0.2);
}

// Compute shader for voxel data processing (if needed)
kernel void processVoxelData(
    texture3d<float, access::read> inputVoxels [[texture(0)]],
    texture3d<float, access::write> outputVoxels [[texture(1)]],
    constant Uniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 128 || gid.y >= 128 || gid.z >= 128) return;

    // Read voxel data
    float4 voxel = inputVoxels.read(gid);

    // Apply temporal animation based on frame index
    float phase = float(uniforms.frameIndex) * 0.1 + float(gid.z) * 0.05;
    float pulse = sin(phase + uniforms.time * 2.0) * 0.5 + 0.5;

    // Modify voxel based on 3D position
    voxel.rgb *= pulse;

    // Write processed voxel
    outputVoxels.write(voxel, gid);
}