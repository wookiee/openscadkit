/*
 *  OpenSCAD C Bridge - Swift Interoperability Layer
 *
 *  This file implements the C API defined in COpenSCAD.h for use with
 *  Swift Package Manager and iOS/macOS apps.
 *
 *  Copyright (C) 2024 OpenSCAD Developers
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 */

#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <cmath>
#include <cstring>
#include <sstream>

// OpenSCAD core headers
#include "openscad.h"
#include "core/Builtins.h"
#include "core/SourceFile.h"
#include "core/Tree.h"
#include "core/Context.h"
#include "core/BuiltinContext.h"
#include "core/EvaluationSession.h"
#include "core/node.h"
#include "platform/PlatformUtils.h"

// Geometry headers
#include "geometry/GeometryEvaluator.h"
#include "geometry/PolySet.h"
#include "geometry/PolySetUtils.h"
#include "geometry/Geometry.h"

// For capturing console output
#include <iostream>
#include <streambuf>

// C API header
extern "C" {

/// Opaque render result structure
struct OpenSCADRenderResult {
    bool success;
    std::string error_message;
    std::string console_output;

    std::vector<float> positions;
    std::vector<float> normals;
    std::vector<uint32_t> indices;

    size_t vertex_count;
    size_t triangle_count;
};

} // extern "C"

namespace {

// Flag to track if OpenSCAD has been initialized
static std::atomic<bool> g_initialized{false};

// Cancellation flag
static std::atomic<bool> g_cancelled{false};

// Custom stream buffer to capture console output
class CaptureBuffer : public std::streambuf {
public:
    std::string captured;
protected:
    int overflow(int c) override {
        if (c != EOF) {
            captured += static_cast<char>(c);
        }
        return c;
    }
};

// Extract mesh data from PolySet
void extractMeshData(const PolySet& polyset, OpenSCADRenderResult* result) {
    // Get triangulated version if not already triangular
    std::shared_ptr<const PolySet> ps;
    if (!polyset.isTriangular()) {
        auto triangulated = PolySetUtils::tessellate_faces(polyset);
        if (triangulated) {
            ps = std::move(triangulated);
        } else {
            // Fall back to original (use non-owning pointer)
            ps = std::shared_ptr<const PolySet>(&polyset, [](const PolySet*){});
        }
    } else {
        ps = std::shared_ptr<const PolySet>(&polyset, [](const PolySet*){});
    }

    // Reserve space
    size_t vertexCount = ps->vertices.size();
    result->positions.reserve(vertexCount * 3);
    result->normals.reserve(vertexCount * 3);

    // Copy vertices and initialize normals
    for (const auto& v : ps->vertices) {
        result->positions.push_back(static_cast<float>(v.x()));
        result->positions.push_back(static_cast<float>(v.y()));
        result->positions.push_back(static_cast<float>(v.z()));
        result->normals.push_back(0.0f);
        result->normals.push_back(0.0f);
        result->normals.push_back(0.0f);
    }

    // Copy indices and compute normals
    for (const auto& face : ps->indices) {
        if (face.size() < 3) continue;

        uint32_t i0 = face[0];
        uint32_t i1 = face[1];
        uint32_t i2 = face[2];

        result->indices.push_back(i0);
        result->indices.push_back(i1);
        result->indices.push_back(i2);

        // Compute face normal
        if (i0 < vertexCount && i1 < vertexCount && i2 < vertexCount) {
            const auto& v0 = ps->vertices[i0];
            const auto& v1 = ps->vertices[i1];
            const auto& v2 = ps->vertices[i2];

            auto edge1 = v1 - v0;
            auto edge2 = v2 - v0;
            auto normal = edge1.cross(edge2);

            double len = normal.norm();
            if (len > 0) {
                normal /= len;

                // Accumulate normals for averaging
                for (uint32_t idx : {i0, i1, i2}) {
                    result->normals[idx * 3 + 0] += static_cast<float>(normal.x());
                    result->normals[idx * 3 + 1] += static_cast<float>(normal.y());
                    result->normals[idx * 3 + 2] += static_cast<float>(normal.z());
                }
            }
        }
    }

    // Normalize accumulated normals
    for (size_t i = 0; i < vertexCount; ++i) {
        float nx = result->normals[i * 3 + 0];
        float ny = result->normals[i * 3 + 1];
        float nz = result->normals[i * 3 + 2];
        float len = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 0) {
            result->normals[i * 3 + 0] = nx / len;
            result->normals[i * 3 + 1] = ny / len;
            result->normals[i * 3 + 2] = nz / len;
        } else {
            // Default normal pointing up
            result->normals[i * 3 + 0] = 0.0f;
            result->normals[i * 3 + 1] = 0.0f;
            result->normals[i * 3 + 2] = 1.0f;
        }
    }

    result->vertex_count = vertexCount;
    result->triangle_count = result->indices.size() / 3;
}

} // anonymous namespace

// C API Implementation
extern "C" {

int openscad_init(void) {
    if (g_initialized.exchange(true)) {
        return 0; // Already initialized
    }

    try {
        // Register application path (required for PlatformUtils)
        // Use current directory as the "application path" for embedded use
        PlatformUtils::registerApplicationPath(".");

        Builtins::instance()->initialize();
        return 0;
    } catch (...) {
        g_initialized = false;
        return -1;
    }
}

OpenSCADRenderResult* openscad_render(const char* scad_source, const char* fonts_path) {
    (void)fonts_path; // TODO: Use for FontConfig initialization

    auto* result = new OpenSCADRenderResult();
    result->success = false;
    result->vertex_count = 0;
    result->triangle_count = 0;

    // Reset cancellation flag
    g_cancelled = false;

    // Ensure initialized
    if (!g_initialized) {
        if (openscad_init() != 0) {
            result->error_message = "Failed to initialize OpenSCAD engine";
            return result;
        }
    }

    // Capture console output
    CaptureBuffer capture;
    std::streambuf* old_cout = std::cout.rdbuf(&capture);
    std::streambuf* old_cerr = std::cerr.rdbuf(&capture);

    try {
        // Parse the source code
        SourceFile* source_file = nullptr;
        std::string filename = "<string>";
        std::string source_str(scad_source);

        bool parse_result = parse(source_file, source_str, filename, filename, 0);

        if (!parse_result || !source_file) {
            result->error_message = "Failed to parse OpenSCAD source";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            return result;
        }

        // Check for cancellation
        if (g_cancelled) {
            result->error_message = "Render cancelled";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            delete source_file;
            return result;
        }

        // Create evaluation session
        EvaluationSession session{""};

        // Create builtin context
        ContextHandle<BuiltinContext> builtin_context{Context::create<BuiltinContext>(&session)};

        // Reset node index counter
        AbstractNode::resetIndexCounter();

        // Instantiate the module
        std::shared_ptr<const FileContext> file_context;
        auto root_node = source_file->instantiate(
            builtin_context->get_shared_ptr(),
            &file_context
        );

        if (!root_node) {
            result->error_message = "Failed to instantiate module";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            delete source_file;
            return result;
        }

        // Check for cancellation
        if (g_cancelled) {
            result->error_message = "Render cancelled";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            delete source_file;
            return result;
        }

        // Create tree from root node
        Tree tree(root_node);

        // Evaluate geometry
        GeometryEvaluator evaluator(tree);
        auto geometry = evaluator.evaluateGeometry(*tree.root(), false);

        if (!geometry) {
            result->error_message = "Failed to evaluate geometry";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            delete source_file;
            return result;
        }

        // Check for cancellation
        if (g_cancelled) {
            result->error_message = "Render cancelled";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            delete source_file;
            return result;
        }

        // Convert to PolySet
        auto polyset = PolySetUtils::getGeometryAsPolySet(geometry);

        if (!polyset || polyset->isEmpty()) {
            result->error_message = "Geometry produced no mesh data";
            result->console_output = capture.captured;
            std::cout.rdbuf(old_cout);
            std::cerr.rdbuf(old_cerr);
            delete source_file;
            return result;
        }

        // Extract mesh data
        extractMeshData(*polyset, result);

        result->success = true;
        result->console_output = capture.captured;

        delete source_file;

    } catch (const std::exception& e) {
        result->error_message = std::string("Exception: ") + e.what();
        result->console_output = capture.captured;
    } catch (...) {
        result->error_message = "Unknown exception during render";
        result->console_output = capture.captured;
    }

    // Restore cout/cerr
    std::cout.rdbuf(old_cout);
    std::cerr.rdbuf(old_cerr);

    return result;
}

bool openscad_result_success(const OpenSCADRenderResult* result) {
    return result ? result->success : false;
}

const char* openscad_result_error(const OpenSCADRenderResult* result) {
    if (!result) return "";
    return result->error_message.c_str();
}

const char* openscad_result_console(const OpenSCADRenderResult* result) {
    if (!result) return "";
    return result->console_output.c_str();
}

size_t openscad_result_vertex_count(const OpenSCADRenderResult* result) {
    return result ? result->vertex_count : 0;
}

size_t openscad_result_triangle_count(const OpenSCADRenderResult* result) {
    return result ? result->triangle_count : 0;
}

const float* openscad_result_positions(const OpenSCADRenderResult* result) {
    if (!result || result->positions.empty()) return nullptr;
    return result->positions.data();
}

const float* openscad_result_normals(const OpenSCADRenderResult* result) {
    if (!result || result->normals.empty()) return nullptr;
    return result->normals.data();
}

const uint32_t* openscad_result_indices(const OpenSCADRenderResult* result) {
    if (!result || result->indices.empty()) return nullptr;
    return result->indices.data();
}

void openscad_result_free(OpenSCADRenderResult* result) {
    delete result;
}

void openscad_cancel(void) {
    g_cancelled = true;
}

const char* openscad_version(void) {
    static const char* version = "OpenSCAD Embedded 2024.12";
    return version;
}

} // extern "C"
