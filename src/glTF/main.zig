const std = @import("std");
const json = std.json;
const ArrayList = std.ArrayList;

const GLB_MAGIC = 0x46546C67; // "glTF"
const GLB_VERSION = 2;
const JSON_CHUNK_TYPE = 0x4E4F534A; // "JSON"
const BIN_CHUNK_TYPE = 0x004E4942; // "BIN\0"

const GLBHeader = packed struct {
    magic: u32,
    version: u32,
    length: u32,
};

const ChunkHeader = packed struct {
    length: u32,
    type: u32,
};

// Cube vertices (8 vertices, each with 3 position coordinates)
const cube_positions = [_]f32{
    -1.0, -1.0, -1.0, // 0: left-bottom-back
    1.0, -1.0, -1.0, // 1: right-bottom-back
    1.0, 1.0, -1.0, // 2: right-top-back
    -1.0, 1.0, -1.0, // 3: left-top-back
    -1.0, -1.0, 1.0, // 4: left-bottom-front
    1.0, -1.0, 1.0, // 5: right-bottom-front
    1.0, 1.0, 1.0, // 6: right-top-front
    -1.0, 1.0, 1.0, // 7: left-top-front
};

// Cube normals (6 faces, each with a normal vector)
const cube_normals = [_]f32{
    0.0, 0.0, -1.0, // back face
    0.0, 0.0, 1.0, // front face
    -1.0, 0.0, 0.0, // left face
    1.0, 0.0, 0.0, // right face
    0.0, -1.0, 0.0, // bottom face
    0.0, 1.0, 0.0, // top face
};

// Cube indices (12 triangles, 2 per face)
const cube_indices = [_]u16{
    0, 1, 2, 0, 2, 3, // back face
    4, 6, 5, 4, 7, 6, // front face
    0, 3, 7, 0, 7, 4, // left face
    1, 5, 6, 1, 6, 2, // right face
    0, 4, 5, 0, 5, 1, // bottom face
    3, 2, 6, 3, 6, 7, // top face
};

fn writeGLB(filename: []const u8) !void {
    // Create the JSON content for the glTF scene
    const gltf_json =
        \\{
        \\  "asset": {
        \\    "version": "2.0",
        \\    "generator": "Zig GLB Writer"
        \\  },
        \\  "scene": 0,
        \\  "scenes": [
        \\    {
        \\      "nodes": [0]
        \\    }
        \\  ],
        \\  "nodes": [
        \\    {
        \\      "mesh": 0
        \\    }
        \\  ],
        \\  "meshes": [
        \\    {
        \\      "primitives": [
        \\        {
        \\          "attributes": {
        \\            "POSITION": 0,
        \\            "NORMAL": 1
        \\          },
        \\          "indices": 2,
        \\          "material": 0
        \\        }
        \\      ]
        \\    }
        \\  ],
        \\  "materials": [
        \\    {
        \\      "pbrMetallicRoughness": {
        \\        "baseColorFactor": [1.0, 1.0, 0.0, 1.0],
        \\        "metallicFactor": 0.0,
        \\        "roughnessFactor": 0.5
        \\      }
        \\    }
        \\  ],
        \\  "accessors": [
        \\    {
        \\      "bufferView": 0,
        \\      "componentType": 5126,
        \\      "count": 8,
        \\      "type": "VEC3",
        \\      "min": [-1.0, -1.0, -1.0],
        \\      "max": [1.0, 1.0, 1.0]
        \\    },
        \\    {
        \\      "bufferView": 1,
        \\      "componentType": 5126,
        \\      "count": 8,
        \\      "type": "VEC3"
        \\    },
        \\    {
        \\      "bufferView": 2,
        \\      "componentType": 5123,
        \\      "count": 36,
        \\      "type": "SCALAR"
        \\    }
        \\  ],
        \\  "bufferViews": [
        \\    {
        \\      "buffer": 0,
        \\      "byteOffset": 0,
        \\      "byteLength": 96,
        \\      "target": 34962
        \\    },
        \\    {
        \\      "buffer": 0,
        \\      "byteOffset": 96,
        \\      "byteLength": 96,
        \\      "target": 34962
        \\    },
        \\    {
        \\      "buffer": 0,
        \\      "byteOffset": 192,
        \\      "byteLength": 72,
        \\      "target": 34963
        \\    }
        \\  ],
        \\  "buffers": [
        \\    {
        \\      "byteLength": 264
        \\    }
        \\  ]
        \\}
    ;

    // Calculate sizes
    const json_size = gltf_json.len;
    const json_padded_size = (json_size + 3) & ~@as(u32, 3); // Pad to 4-byte boundary

    // Binary buffer: positions (96 bytes) + normals (96 bytes) + indices (72 bytes) = 264 bytes
    const positions_size = cube_positions.len * @sizeOf(f32);
    const normals_size = 8 * 3 * @sizeOf(f32); // 8 vertices * 3 components * 4 bytes
    const indices_size = cube_indices.len * @sizeOf(u16);
    const binary_size = positions_size + normals_size + indices_size;
    const binary_padded_size = (binary_size + 3) & ~@as(u32, 3);

    const total_size = @sizeOf(GLBHeader) +
        @sizeOf(ChunkHeader) + json_padded_size +
        @sizeOf(ChunkHeader) + binary_padded_size;

    // Create file
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    var writer = file.writer();

    // Write GLB header
    const glb_header = GLBHeader{
        .magic = GLB_MAGIC,
        .version = GLB_VERSION,
        .length = @intCast(total_size),
    };
    try writer.writeStruct(glb_header);

    // Write JSON chunk header
    const json_chunk_header = ChunkHeader{
        .length = json_padded_size,
        .type = JSON_CHUNK_TYPE,
    };
    try writer.writeStruct(json_chunk_header);

    // Write JSON content
    try writer.writeAll(gltf_json);

    // Pad JSON chunk to 4-byte boundary with spaces
    const json_padding = json_padded_size - json_size;
    for (0..json_padding) |_| {
        try writer.writeByte(' ');
    }

    // Write binary chunk header
    const bin_chunk_header = ChunkHeader{
        .length = binary_padded_size,
        .type = BIN_CHUNK_TYPE,
    };
    try writer.writeStruct(bin_chunk_header);

    // Write binary data
    // Positions
    const positions_bytes = std.mem.asBytes(&cube_positions);
    try writer.writeAll(positions_bytes);

    // Normals (expand to per-vertex normals)
    const vertex_normals = [_]f32{
        0.0, 0.0, -1.0, // vertex 0: back face
        0.0, 0.0, -1.0, // vertex 1: back face
        0.0, 0.0, -1.0, // vertex 2: back face
        0.0, 0.0, -1.0, // vertex 3: back face
        0.0, 0.0, 1.0, // vertex 4: front face
        0.0, 0.0, 1.0, // vertex 5: front face
        0.0, 0.0, 1.0, // vertex 6: front face
        0.0, 0.0, 1.0, // vertex 7: front face
    };

    const normals_bytes = std.mem.asBytes(&vertex_normals);
    try writer.writeAll(normals_bytes);

    // Indices
    const indices_bytes = std.mem.asBytes(&cube_indices);
    try writer.writeAll(indices_bytes);

    // Pad binary chunk to 4-byte boundary with zeros
    const binary_padding = binary_padded_size - binary_size;
    for (0..binary_padding) |_| {
        try writer.writeByte(0);
    }

    std.debug.print("GLB file '{s}' created successfully!\n", .{filename});
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    try writeGLB("yellow_cube.glb");
}
