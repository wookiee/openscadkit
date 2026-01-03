//
//  MetalCSGShaders.metal
//  OpenSCADMetal
//
//  Metal shaders for CSG preview rendering.
//  Implements depth-only passes for CSG computation and shading passes for final display.
//

#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// MARK: - Vertex Shader Inputs (for [[stage_in]] with vertex descriptors)

struct CSGDepthVertexIn {
    float3 position [[attribute(0)]];
};

struct CSGShadingVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

// MARK: - Vertex Shader Outputs

struct CSGDepthVertexOut {
    float4 position [[position]];
};

struct CSGShadingVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 viewDirection;
    float4 color;
};

// MARK: - CSG Depth Pass Shaders
// These shaders are used during CSG computation. They only write to the depth buffer.

/// Depth-only vertex shader for CSG computation
/// Takes position-only vertices and transforms to clip space.
vertex CSGDepthVertexOut csg_depth_vertex(
    CSGDepthVertexIn in [[stage_in]],
    constant CSGUniforms& uniforms [[buffer(CSGBufferIndexUniforms)]]
) {
    CSGDepthVertexOut out;
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * position;
    return out;
}

/// Depth-only fragment shader for CSG computation
/// Writes nothing to color buffer; depth is written by hardware.
fragment void csg_depth_fragment(CSGDepthVertexOut in [[stage_in]]) {
    // Empty - only depth is written by hardware
    // This is called during CSG depth pass where we compute which surfaces are visible
}

// MARK: - CSG Shading Pass Shaders
// These shaders render the final visible surfaces after CSG computation.

/// Shading pass vertex shader
/// Transforms vertices and prepares data for lighting calculations.
vertex CSGShadingVertexOut csg_shading_vertex(
    CSGShadingVertexIn in [[stage_in]],
    constant CSGUniforms& uniforms [[buffer(CSGBufferIndexUniforms)]]
) {
    CSGShadingVertexOut out;

    float4 position = float4(in.position, 1.0);
    float3 normal = in.normal;

    out.position = uniforms.modelViewProjectionMatrix * position;

    // Transform normal to world space
    out.worldNormal = normalize((uniforms.normalMatrix * float4(normal, 0.0)).xyz);

    // View direction (camera at origin in view space)
    float4 viewPosition = uniforms.modelViewMatrix * position;
    out.viewDirection = normalize(-viewPosition.xyz);

    // Default color (will be overridden by material)
    out.color = float4(0.8, 0.8, 0.8, 1.0);

    return out;
}

/// Shading pass fragment shader with simple Blinn-Phong lighting
fragment float4 csg_shading_fragment(
    CSGShadingVertexOut in [[stage_in]],
    constant CSGMaterial& material [[buffer(CSGBufferIndexMaterial)]],
    constant CSGLight& light [[buffer(CSGBufferIndexLight)]]
) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(-light.direction);
    float3 V = normalize(in.viewDirection);
    float3 H = normalize(L + V);

    // Ambient
    float3 ambient = 0.1 * material.baseColor.rgb;

    // Diffuse
    float NdotL = max(dot(N, L), 0.0);
    float3 diffuse = NdotL * material.baseColor.rgb * light.color.rgb * light.intensity;

    // Specular (Blinn-Phong)
    float NdotH = max(dot(N, H), 0.0);
    float shininess = mix(8.0, 128.0, 1.0 - material.roughness);
    float spec = pow(NdotH, shininess) * (1.0 - material.roughness);
    float3 specular = spec * light.color.rgb * light.intensity * material.metallic;

    float3 color = ambient + diffuse + specular;

    return float4(color, material.baseColor.a);
}

/// Simple flat shading fragment shader (for debugging/preview)
fragment float4 csg_flat_fragment(
    CSGShadingVertexOut in [[stage_in]],
    constant CSGMaterial& material [[buffer(CSGBufferIndexMaterial)]]
) {
    float3 N = normalize(in.worldNormal);

    // Simple directional light from camera
    float3 L = normalize(float3(0.3, 0.5, 1.0));
    float NdotL = max(dot(N, L), 0.0);

    float3 color = material.baseColor.rgb * (0.3 + 0.7 * NdotL);

    return float4(color, material.baseColor.a);
}

/// Per-vertex color fragment shader
fragment float4 csg_colored_fragment(
    CSGShadingVertexOut in [[stage_in]]
) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(float3(0.3, 0.5, 1.0));
    float NdotL = max(dot(N, L), 0.0);

    float3 color = in.color.rgb * (0.3 + 0.7 * NdotL);

    return float4(color, in.color.a);
}

// MARK: - Stencil ID Shaders
// For SCS algorithm: encode primitive ID in stencil or color

/// Fragment shader that outputs primitive ID as color (for debugging)
fragment float4 csg_id_fragment(
    CSGDepthVertexOut in [[stage_in]],
    constant uint& primitiveID [[buffer(2)]]
) {
    // Encode ID in color channels for debugging
    float r = float((primitiveID >> 0) & 0xFF) / 255.0;
    float g = float((primitiveID >> 8) & 0xFF) / 255.0;
    float b = float((primitiveID >> 16) & 0xFF) / 255.0;
    return float4(r, g, b, 1.0);
}
