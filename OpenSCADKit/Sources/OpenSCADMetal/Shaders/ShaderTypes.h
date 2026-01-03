//
//  ShaderTypes.h
//  OpenSCADMetal
//
//  Shared type definitions between Metal shaders and Swift/C++ code.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// MARK: - Vertex Buffer Layouts

/// Vertex layout for CSG depth pass (position only)
typedef struct {
    simd_float3 position;
} CSGDepthVertex;

/// Vertex layout for shading pass (position + normal)
typedef struct {
    simd_float3 position;
    simd_float3 normal;
} CSGShadingVertex;

/// Full vertex layout matching OpenCSG's interleaved VBO format
typedef struct {
    simd_float3 position;
    simd_float3 normal;
    simd_float4 color;
} CSGFullVertex;

// MARK: - Uniform Buffers

/// Per-frame uniforms
typedef struct {
    simd_float4x4 modelViewProjectionMatrix;
    simd_float4x4 modelViewMatrix;
    simd_float4x4 normalMatrix;
} CSGUniforms;

/// Material properties for shading pass
typedef struct {
    simd_float4 baseColor;
    float roughness;
    float metallic;
    float padding[2];
} CSGMaterial;

/// Light properties
typedef struct {
    simd_float3 direction;
    float intensity;
    simd_float4 color;
} CSGLight;

// MARK: - Buffer Indices

/// Vertex buffer indices
typedef enum {
    CSGBufferIndexVertices = 0,
    CSGBufferIndexUniforms = 1,
    CSGBufferIndexMaterial = 2,
    CSGBufferIndexLight = 3
} CSGBufferIndex;

/// Vertex attribute indices
typedef enum {
    CSGVertexAttributePosition = 0,
    CSGVertexAttributeNormal = 1,
    CSGVertexAttributeColor = 2
} CSGVertexAttribute;

// MARK: - CSG Operation Types

/// CSG operation types (matches OpenCSG::Operation)
typedef enum {
    CSGOperationIntersection = 0,
    CSGOperationSubtraction = 1
} CSGOperationType;

#endif /* ShaderTypes_h */
