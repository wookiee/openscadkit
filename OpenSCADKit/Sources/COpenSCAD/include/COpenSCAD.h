/*
 *  COpenSCAD - Swift Package C Bridge Header
 *
 *  This header re-exports the OpenSCAD C bridge API for use in Swift.
 *  The actual implementation is in the OpenSCAD XCFramework.
 */

#ifndef COPENSCAD_H
#define COPENSCAD_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a render result
typedef struct OpenSCADRenderResult OpenSCADRenderResult;

/// Initialize the OpenSCAD engine (call once at app startup)
/// @return 0 on success, non-zero on failure
int openscad_init(void);

/// Render OpenSCAD source code to a triangle mesh
///
/// @param scad_source The OpenSCAD source code to render (null-terminated)
/// @param fonts_path Optional path to fonts directory (can be NULL)
/// @return Handle to render result, or NULL on failure. Must be freed with openscad_result_free()
OpenSCADRenderResult* openscad_render(const char* scad_source, const char* fonts_path);

/// Check if render was successful
/// @param result The render result to check
/// @return true if render succeeded, false otherwise
bool openscad_result_success(const OpenSCADRenderResult* result);

/// Get error message (empty string if success)
/// @param result The render result
/// @return Error message string (valid until result is freed)
const char* openscad_result_error(const OpenSCADRenderResult* result);

/// Get console output (echo statements, warnings)
/// @param result The render result
/// @return Console output string (valid until result is freed)
const char* openscad_result_console(const OpenSCADRenderResult* result);

/// Get number of vertices in the mesh
/// @param result The render result
/// @return Number of vertices
size_t openscad_result_vertex_count(const OpenSCADRenderResult* result);

/// Get number of triangles in the mesh
/// @param result The render result
/// @return Number of triangles
size_t openscad_result_triangle_count(const OpenSCADRenderResult* result);

/// Get vertex positions array (3 floats per vertex: x, y, z)
/// @param result The render result
/// @return Pointer to positions array, or NULL if no mesh data
const float* openscad_result_positions(const OpenSCADRenderResult* result);

/// Get vertex normals array (3 floats per vertex: nx, ny, nz)
/// @param result The render result
/// @return Pointer to normals array, or NULL if no mesh data
const float* openscad_result_normals(const OpenSCADRenderResult* result);

/// Get triangle indices array (3 uint32_t per triangle)
/// @param result The render result
/// @return Pointer to indices array, or NULL if no mesh data
const uint32_t* openscad_result_indices(const OpenSCADRenderResult* result);

/// Free a render result
/// @param result The render result to free
void openscad_result_free(OpenSCADRenderResult* result);

/// Cancel any in-progress render
void openscad_cancel(void);

/// Get OpenSCAD version string
/// @return Version string
const char* openscad_version(void);

#ifdef __cplusplus
}
#endif

#endif /* COPENSCAD_H */
