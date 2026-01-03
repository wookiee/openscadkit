//
//  main.swift
//  openscad
//
//  Command-line interface for OpenSCAD rendering.
//  Renders SCAD files or inline code to STL format.
//
//  Usage:
//    openscad input.scad -o output.stl
//    openscad -e "cube([10,10,10]);" -o output.stl
//    openscad --version
//

import Foundation
import OpenSCADCore

// MARK: - CLI Entry Point

@main
struct OpenSCADCLI {
    static func main() async {
        let args = CommandLine.arguments

        // Handle --version
        if args.contains("--version") || args.contains("-v") {
            print(OpenSCADEngine.version())
            return
        }

        // Handle --help
        if args.contains("--help") || args.contains("-h") || args.count == 1 {
            printUsage()
            return
        }

        // Parse arguments
        var inputFile: String?
        var outputFile: String?
        var inlineSource: String?
        var verbose = false

        var i = 1
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "-o", "--output":
                if i + 1 < args.count {
                    outputFile = args[i + 1]
                    i += 1
                } else {
                    printError("Missing output file after \(arg)")
                    exit(1)
                }

            case "-e", "--eval":
                if i + 1 < args.count {
                    inlineSource = args[i + 1]
                    i += 1
                } else {
                    printError("Missing SCAD code after \(arg)")
                    exit(1)
                }

            case "--verbose":
                verbose = true

            default:
                if arg.hasPrefix("-") {
                    printError("Unknown option: \(arg)")
                    exit(1)
                } else if inputFile == nil {
                    inputFile = arg
                } else {
                    printError("Unexpected argument: \(arg)")
                    exit(1)
                }
            }
            i += 1
        }

        // Determine source
        let source: String
        if let inline = inlineSource {
            source = inline
        } else if let file = inputFile {
            do {
                source = try String(contentsOfFile: file, encoding: .utf8)
            } catch {
                printError("Failed to read input file: \(error.localizedDescription)")
                exit(1)
            }
        } else {
            printError("No input file or -e code specified")
            printUsage()
            exit(1)
        }

        // Determine output
        let output: String
        if let out = outputFile {
            output = out
        } else if let input = inputFile {
            // Default: replace .scad with .stl
            let url = URL(fileURLWithPath: input)
            output = url.deletingPathExtension().appendingPathExtension("stl").path
        } else {
            printError("Output file required when using -e (use -o output.stl)")
            exit(1)
        }

        // Render
        if verbose {
            printInfo("Rendering...")
        }

        let engine = OpenSCADEngine()

        do {
            let startTime = Date()
            let result = try await engine.render(source: source)
            let elapsed = Date().timeIntervalSince(startTime)

            if !result.success {
                printError("Render failed: \(result.errorMessage ?? "Unknown error")")
                if !result.consoleOutput.isEmpty {
                    fputs("\(result.consoleOutput)\n", stderr)
                }
                exit(1)
            }

            if result.triangleCount == 0 {
                printError("Render produced no geometry")
                if !result.consoleOutput.isEmpty {
                    fputs("\(result.consoleOutput)\n", stderr)
                }
                exit(1)
            }

            // Write STL
            let stlData = generateBinarySTL(result: result)
            try stlData.write(to: URL(fileURLWithPath: output))

            if verbose {
                printInfo("Wrote \(result.triangleCount) triangles to \(output)")
                printInfo(String(format: "Time: %.2fs", elapsed))
            }

            // Print console output if any
            if !result.consoleOutput.isEmpty && verbose {
                print(result.consoleOutput)
            }

        } catch {
            printError("Render error: \(error.localizedDescription)")
            exit(1)
        }
    }
}

// MARK: - STL Generation

/// Generates binary STL data from a RenderResult
func generateBinarySTL(result: RenderResult) -> Data {
    var data = Data()

    // 80-byte header
    let header = "OpenSCADKit CLI Export".padding(toLength: 80, withPad: "\0", startingAt: 0)
    data.append(contentsOf: header.utf8.prefix(80))
    if data.count < 80 {
        data.append(contentsOf: [UInt8](repeating: 0, count: 80 - data.count))
    }

    // Triangle count (4 bytes, little-endian)
    var triangleCount = UInt32(result.triangleCount)
    data.append(contentsOf: withUnsafeBytes(of: &triangleCount) { Array($0) })

    // Each triangle: normal (12 bytes) + 3 vertices (36 bytes) + attribute (2 bytes) = 50 bytes
    for t in 0..<result.triangleCount {
        let i0 = Int(result.indices[t * 3])
        let i1 = Int(result.indices[t * 3 + 1])
        let i2 = Int(result.indices[t * 3 + 2])

        // Use first vertex's normal for face normal
        let nx = result.normals[i0 * 3]
        let ny = result.normals[i0 * 3 + 1]
        let nz = result.normals[i0 * 3 + 2]

        // Normal
        appendFloat(&data, nx)
        appendFloat(&data, ny)
        appendFloat(&data, nz)

        // Vertex 1
        appendFloat(&data, result.positions[i0 * 3])
        appendFloat(&data, result.positions[i0 * 3 + 1])
        appendFloat(&data, result.positions[i0 * 3 + 2])

        // Vertex 2
        appendFloat(&data, result.positions[i1 * 3])
        appendFloat(&data, result.positions[i1 * 3 + 1])
        appendFloat(&data, result.positions[i1 * 3 + 2])

        // Vertex 3
        appendFloat(&data, result.positions[i2 * 3])
        appendFloat(&data, result.positions[i2 * 3 + 1])
        appendFloat(&data, result.positions[i2 * 3 + 2])

        // Attribute byte count (2 bytes, usually 0)
        data.append(contentsOf: [0, 0] as [UInt8])
    }

    return data
}

func appendFloat(_ data: inout Data, _ value: Float) {
    var v = value
    data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
}

// MARK: - Output Helpers

func printUsage() {
    let usage = """
    Usage: openscad [options] <input.scad>

    Options:
      -o, --output <file>   Output STL file (default: input with .stl extension)
      -e, --eval <code>     Render inline SCAD code instead of file
      --verbose             Show detailed output
      -v, --version         Show OpenSCAD version
      -h, --help            Show this help message

    Examples:
      openscad model.scad                    # Render model.scad to model.stl
      openscad model.scad -o out.stl         # Render to specific output file
      openscad -e "cube([10,10,10]);" -o cube.stl
    """
    print(usage)
}

func printError(_ message: String) {
    fputs("Error: \(message)\n", stderr)
}

func printInfo(_ message: String) {
    print(message)
}
