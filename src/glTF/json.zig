const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Component types for accessors
pub const ComponentType = enum(u32) {
    byte = 5120,
    unsigned_byte = 5121,
    short = 5122,
    unsigned_short = 5123,
    unsigned_int = 5125,
    float = 5126,
};

// Accessor data types
pub const AccessorType = enum {
    scalar,
    vec2,
    vec3,
    vec4,
    mat2,
    mat3,
    mat4,

    pub fn fromString(str: []const u8) !AccessorType {
        if (std.mem.eql(u8, str, "SCALAR")) return .scalar;
        if (std.mem.eql(u8, str, "VEC2")) return .vec2;
        if (std.mem.eql(u8, str, "VEC3")) return .vec3;
        if (std.mem.eql(u8, str, "VEC4")) return .vec4;
        if (std.mem.eql(u8, str, "MAT2")) return .mat2;
        if (std.mem.eql(u8, str, "MAT3")) return .mat3;
        if (std.mem.eql(u8, str, "MAT4")) return .mat4;
        return error.InvalidAccessorType;
    }
};

// GL primitive modes
pub const PrimitiveMode = enum(u32) {
    points = 0,
    lines = 1,
    line_loop = 2,
    line_strip = 3,
    triangles = 4,
    triangle_strip = 5,
    triangle_fan = 6,
};

// Asset information (required)
pub const Asset = struct {
    version: []const u8,
    generator: ?[]const u8 = null,
    min_version: ?[]const u8 = null,
    copyright: ?[]const u8 = null,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        if (self.generator) |generator| allocator.free(generator);
        if (self.min_version) |min_version| allocator.free(min_version);
        if (self.copyright) |copyright| allocator.free(copyright);
    }

    // pub fn format(
    //     self: *const Self,
    //     comptime fmt: []const u8,
    //     options: std.fmt.FormatOptions,
    //     writer: anytype,
    // ) !void {
    //     _ = fmt;
    //     _ = options;

    //     try writer.print("Version: {s}\n", .{self.version});
    //     try writer.print("Generator: {?s}", .{self.generator});
    // }
};

// Buffer - raw binary data
pub const Buffer = struct {
    byte_length: u32,
    uri: ?[]const u8 = null,
    name: ?[]const u8 = null,
};

// BufferView - chunk of buffer data
pub const BufferView = struct {
    buffer: u32,
    byte_offset: u32 = 0,
    byte_length: u32,
    byte_stride: ?u32 = null,
    target: ?u32 = null,
    name: ?[]const u8 = null,
};

// Accessor - data layout descriptor
pub const Accessor = struct {
    buffer_view: ?u32 = null,
    byte_offset: u32 = 0,
    component_type: ComponentType,
    normalized: bool = false,
    count: u32,
    type: AccessorType,
    max: ?[]f64 = null,
    min: ?[]f64 = null,
    sparse: ?Sparse = null,
    name: ?[]const u8 = null,

    pub const Sparse = struct {
        count: u32,
        indices: SparseIndices,
        values: SparseValues,

        pub const SparseIndices = struct {
            buffer_view: u32,
            byte_offset: u32 = 0,
            component_type: ComponentType,
        };

        pub const SparseValues = struct {
            buffer_view: u32,
            byte_offset: u32 = 0,
        };
    };
};

// Image
pub const Image = struct {
    uri: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
    buffer_view: ?u32 = null,
    name: ?[]const u8 = null,
};

// Sampler
pub const Sampler = struct {
    mag_filter: ?u32 = null,
    min_filter: ?u32 = null,
    wrap_s: u32 = 10497, // GL_REPEAT
    wrap_t: u32 = 10497, // GL_REPEAT
    name: ?[]const u8 = null,
};

// Texture
pub const Texture = struct {
    sampler: ?u32 = null,
    source: ?u32 = null,
    name: ?[]const u8 = null,
};

// Material
pub const Material = struct {
    name: ?[]const u8 = null,
    pbr_metallic_roughness: ?PbrMetallicRoughness = null,
    normal_texture: ?NormalTextureInfo = null,
    occlusion_texture: ?OcclusionTextureInfo = null,
    emissive_texture: ?TextureInfo = null,
    emissive_factor: [3]f64 = [_]f64{ 0.0, 0.0, 0.0 },
    alpha_mode: []const u8 = "OPAQUE",
    alpha_cutoff: f64 = 0.5,
    double_sided: bool = false,

    pub const PbrMetallicRoughness = struct {
        base_color_factor: [4]f64 = [_]f64{ 1.0, 1.0, 1.0, 1.0 },
        base_color_texture: ?TextureInfo = null,
        metallic_factor: f64 = 1.0,
        roughness_factor: f64 = 1.0,
        metallic_roughness_texture: ?TextureInfo = null,
    };

    pub const TextureInfo = struct {
        index: u32,
        tex_coord: u32 = 0,
    };

    pub const NormalTextureInfo = struct {
        index: u32,
        tex_coord: u32 = 0,
        scale: f64 = 1.0,
    };

    pub const OcclusionTextureInfo = struct {
        index: u32,
        tex_coord: u32 = 0,
        strength: f64 = 1.0,
    };
};

// Mesh primitive
pub const Primitive = struct {
    attributes: std.StringHashMap(u32),
    indices: ?u32 = null,
    material: ?u32 = null,
    mode: PrimitiveMode = .triangles,
    targets: ?[]std.StringHashMap(u32) = null,
};

// Mesh
pub const Mesh = struct {
    primitives: []Primitive,
    weights: ?[]f64 = null,
    name: ?[]const u8 = null,
};

// Node
pub const Node = struct {
    camera: ?u32 = null,
    children: ?[]u32 = null,
    skin: ?u32 = null,
    matrix: ?[16]f64 = null,
    mesh: ?u32 = null,
    rotation: [4]f64 = [_]f64{ 0.0, 0.0, 0.0, 1.0 },
    scale: [3]f64 = [_]f64{ 1.0, 1.0, 1.0 },
    translation: [3]f64 = [_]f64{ 0.0, 0.0, 0.0 },
    weights: ?[]f64 = null,
    name: ?[]const u8 = null,
};

// Scene
pub const Scene = struct {
    nodes: ?[]u32 = null,
    name: ?[]const u8 = null,
};

// Animation
pub const Animation = struct {
    channels: []Channel,
    samplers: []AnimationSampler,
    name: ?[]const u8 = null,

    pub const Channel = struct {
        sampler: u32,
        target: Target,

        pub const Target = struct {
            node: ?u32 = null,
            path: []const u8,
        };
    };

    pub const AnimationSampler = struct {
        input: u32,
        interpolation: []const u8 = "LINEAR",
        output: u32,
    };
};

// Skin
pub const Skin = struct {
    inverse_bind_matrices: ?u32 = null,
    skeleton: ?u32 = null,
    joints: []u32,
    name: ?[]const u8 = null,
};

// Main glTF structure
pub const Gltf = struct {
    asset: Asset,
    // scene: ?u32 = null,
    // scenes: ?[]Scene = null,
    // nodes: ?[]Node = null,
    // meshes: ?[]Mesh = null,
    // materials: ?[]Material = null,
    // textures: ?[]Texture = null,
    // images: ?[]Image = null,
    // samplers: ?[]Sampler = null,
    // accessors: ?[]Accessor = null,
    // buffer_views: ?[]BufferView = null,
    // buffers: ?[]Buffer = null,
    // animations: ?[]Animation = null,
    // skins: ?[]Skin = null,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.asset.deinit(allocator);

        // if (self.scenes) |scenes| {
        //     for (scenes) |scene| {
        //         if (scene.nodes) |nodes| allocator.free(nodes);
        //     }
        //     allocator.free(scenes);
        // }

        // if (self.nodes) |nodes| {
        //     for (nodes) |node| {
        //         if (node.children) |children| allocator.free(children);
        //         if (node.weights) |weights| allocator.free(weights);
        //     }
        //     allocator.free(nodes);
        // }

        // if (self.meshes) |meshes| {
        //     for (meshes) |mesh| {
        //         for (mesh.primitives) |primitive| {
        //             @constCast(&primitive.attributes).deinit();
        //             if (primitive.targets) |targets| {
        //                 for (targets) |target| {
        //                     @constCast(&target).deinit();
        //                 }
        //                 allocator.free(targets);
        //             }
        //         }
        //         allocator.free(mesh.primitives);
        //         if (mesh.weights) |weights| allocator.free(weights);
        //     }
        //     allocator.free(meshes);
        // }

        // if (self.materials) |materials| allocator.free(materials);
        // if (self.textures) |textures| allocator.free(textures);
        // if (self.images) |images| allocator.free(images);
        // if (self.samplers) |samplers| allocator.free(samplers);

        // if (self.accessors) |accessors| {
        //     for (accessors) |accessor| {
        //         if (accessor.max) |max| allocator.free(max);
        //         if (accessor.min) |min| allocator.free(min);
        //     }
        //     allocator.free(accessors);
        // }

        // if (self.buffer_views) |buffer_views| allocator.free(buffer_views);
        // if (self.buffers) |buffers| allocator.free(buffers);

        // if (self.animations) |animations| {
        //     for (animations) |animation| {
        //         allocator.free(animation.channels);
        //         allocator.free(animation.samplers);
        //     }
        //     allocator.free(animations);
        // }

        // if (self.skins) |skins| {
        //     for (skins) |skin| {
        //         allocator.free(skin.joints);
        //     }
        //     allocator.free(skins);
        // }
    }

    pub fn parseFromString(allocator: Allocator, json_string: []const u8) !Self {
        var parsed = json.parseFromSlice(json.Value, allocator, json_string, .{}) catch |err| {
            std.log.err("Failed to parse JSON: {}\n", .{err});
            return err;
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse required asset
        const asset_obj = root.get("asset") orelse return error.MissingAsset;
        const asset = try parseAsset(asset_obj.object, allocator);

        const gltf = Self{
            .asset = asset,
        };

        // // Parse optional fields
        // if (root.get("scene")) |scene_val| {
        //     gltf.scene = @intCast(scene_val.integer);
        // }

        // if (root.get("scenes")) |scenes_val| {
        //     gltf.scenes = try parseScenes(allocator, scenes_val.array);
        // }

        // if (root.get("nodes")) |nodes_val| {
        //     gltf.nodes = try parseNodes(allocator, nodes_val.array);
        // }

        // if (root.get("meshes")) |meshes_val| {
        //     gltf.meshes = try parseMeshes(allocator, meshes_val.array);
        // }

        // if (root.get("materials")) |materials_val| {
        //     gltf.materials = try parseMaterials(allocator, materials_val.array);
        // }

        // if (root.get("textures")) |textures_val| {
        //     gltf.textures = try parseTextures(allocator, textures_val.array);
        // }

        // if (root.get("images")) |images_val| {
        //     gltf.images = try parseImages(allocator, images_val.array);
        // }

        // if (root.get("samplers")) |samplers_val| {
        //     gltf.samplers = try parseSamplers(allocator, samplers_val.array);
        // }

        // if (root.get("accessors")) |accessors_val| {
        //     gltf.accessors = try parseAccessors(allocator, accessors_val.array);
        // }

        // if (root.get("bufferViews")) |buffer_views_val| {
        //     gltf.buffer_views = try parseBufferViews(allocator, buffer_views_val.array);
        // }

        // if (root.get("buffers")) |buffers_val| {
        //     gltf.buffers = try parseBuffers(allocator, buffers_val.array);
        // }

        // if (root.get("animations")) |animations_val| {
        //     gltf.animations = try parseAnimations(allocator, animations_val.array);
        // }

        // if (root.get("skins")) |skins_val| {
        //     gltf.skins = try parseSkins(allocator, skins_val.array);
        // }

        return gltf;
    }
};

// Helper parsing functions
fn parseAsset(obj: json.ObjectMap, allocator: std.mem.Allocator) !Asset {
    const version = obj.get("version") orelse return error.MissingVersion;

    return Asset{
        .version = try allocator.dupe(u8, version.string),
        .generator = if (obj.get("generator")) |g| try allocator.dupe(u8, g.string) else null,
        .min_version = if (obj.get("minVersion")) |mv| try allocator.dupe(u8, mv.string) else null,
        .copyright = if (obj.get("copyright")) |c| try allocator.dupe(u8, c.string) else null,
    };
}

fn parseScenes(allocator: Allocator, arr: json.Array) ![]Scene {
    var scenes = try allocator.alloc(Scene, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        scenes[i] = Scene{
            .name = if (obj.get("name")) |n| n.string else null,
            .nodes = if (obj.get("nodes")) |nodes_val| try parseU32Array(allocator, nodes_val.array) else null,
        };
    }

    return scenes;
}

fn parseNodes(allocator: Allocator, arr: json.Array) ![]Node {
    var nodes = try allocator.alloc(Node, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;

        nodes[i] = Node{
            .name = if (obj.get("name")) |n| n.string else null,
            .mesh = if (obj.get("mesh")) |m| @intCast(m.integer) else null,
            .children = if (obj.get("children")) |c| try parseU32Array(allocator, c.array) else null,
        };

        // Parse optional transform arrays
        if (obj.get("translation")) |t| {
            const trans_arr = t.array;
            nodes[i].translation = [_]f64{
                trans_arr.items[0].float,
                trans_arr.items[1].float,
                trans_arr.items[2].float,
            };
        }

        if (obj.get("rotation")) |r| {
            const rot_arr = r.array;
            nodes[i].rotation = [_]f64{
                rot_arr.items[0].float,
                rot_arr.items[1].float,
                rot_arr.items[2].float,
                rot_arr.items[3].float,
            };
        }

        if (obj.get("scale")) |s| {
            const scale_arr = s.array;
            nodes[i].scale = [_]f64{
                scale_arr.items[0].float,
                scale_arr.items[1].float,
                scale_arr.items[2].float,
            };
        }

        if (obj.get("matrix")) |m| {
            const matrix_arr = m.array;
            for (0..16) |j| {
                nodes[i].matrix.?[j] = matrix_arr.items[j].float;
            }
        }
    }

    return nodes;
}

fn parseMeshes(allocator: Allocator, arr: json.Array) ![]Mesh {
    var meshes = try allocator.alloc(Mesh, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        const primitives_arr = obj.get("primitives").?.array;

        var primitives = try allocator.alloc(Primitive, primitives_arr.items.len);

        for (primitives_arr.items, 0..) |prim_item, j| {
            const prim_obj = prim_item.object;

            // Parse attributes
            var attributes = std.StringHashMap(u32).init(allocator);
            if (prim_obj.get("attributes")) |attrs_val| {
                var attrs_iter = attrs_val.object.iterator();
                while (attrs_iter.next()) |entry| {
                    try attributes.put(entry.key_ptr.*, @intCast(entry.value_ptr.integer));
                }
            }

            primitives[j] = Primitive{
                .attributes = attributes,
                .indices = if (prim_obj.get("indices")) |idx| @intCast(idx.integer) else null,
                .material = if (prim_obj.get("material")) |mat| @intCast(mat.integer) else null,
                .mode = if (prim_obj.get("mode")) |mode| @enumFromInt(mode.integer) else .triangles,
            };
        }

        meshes[i] = Mesh{
            .primitives = primitives,
            .name = if (obj.get("name")) |n| n.string else null,
        };
    }

    return meshes;
}

fn parseMaterials(allocator: Allocator, arr: json.Array) ![]Material {
    var materials = try allocator.alloc(Material, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        materials[i] = Material{
            .name = if (obj.get("name")) |n| n.string else null,
            .alpha_mode = if (obj.get("alphaMode")) |am| am.string else "OPAQUE",
            .alpha_cutoff = if (obj.get("alphaCutoff")) |ac| ac.float else 0.5,
            .double_sided = if (obj.get("doubleSided")) |ds| ds.bool else false,
        };

        // Parse emissive factor
        if (obj.get("emissiveFactor")) |ef| {
            const ef_arr = ef.array;
            materials[i].emissive_factor = [_]f64{
                ef_arr.items[0].float,
                ef_arr.items[1].float,
                ef_arr.items[2].float,
            };
        }
    }

    return materials;
}

fn parseTextures(allocator: Allocator, arr: json.Array) ![]Texture {
    var textures = try allocator.alloc(Texture, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        textures[i] = Texture{
            .name = if (obj.get("name")) |n| n.string else null,
            .sampler = if (obj.get("sampler")) |s| @intCast(s.integer) else null,
            .source = if (obj.get("source")) |s| @intCast(s.integer) else null,
        };
    }

    return textures;
}

fn parseImages(allocator: Allocator, arr: json.Array) ![]Image {
    var images = try allocator.alloc(Image, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        images[i] = Image{
            .name = if (obj.get("name")) |n| n.string else null,
            .uri = if (obj.get("uri")) |u| u.string else null,
            .mime_type = if (obj.get("mimeType")) |mt| mt.string else null,
            .buffer_view = if (obj.get("bufferView")) |bv| @intCast(bv.integer) else null,
        };
    }

    return images;
}

fn parseSamplers(allocator: Allocator, arr: json.Array) ![]Sampler {
    var samplers = try allocator.alloc(Sampler, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        samplers[i] = Sampler{
            .name = if (obj.get("name")) |n| n.string else null,
            .mag_filter = if (obj.get("magFilter")) |mf| @intCast(mf.integer) else null,
            .min_filter = if (obj.get("minFilter")) |mf| @intCast(mf.integer) else null,
            .wrap_s = if (obj.get("wrapS")) |ws| @intCast(ws.integer) else 10497,
            .wrap_t = if (obj.get("wrapT")) |wt| @intCast(wt.integer) else 10497,
        };
    }

    return samplers;
}

fn parseAccessors(allocator: Allocator, arr: json.Array) ![]Accessor {
    var accessors = try allocator.alloc(Accessor, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;

        const type_str = obj.get("type").?.string;
        const accessor_type = try AccessorType.fromString(type_str);

        accessors[i] = Accessor{
            .name = if (obj.get("name")) |n| n.string else null,
            .buffer_view = if (obj.get("bufferView")) |bv| @intCast(bv.integer) else null,
            .byte_offset = if (obj.get("byteOffset")) |bo| @intCast(bo.integer) else 0,
            .component_type = @enumFromInt(obj.get("componentType").?.integer),
            .normalized = if (obj.get("normalized")) |n| n.bool else false,
            .count = @intCast(obj.get("count").?.integer),
            .type = accessor_type,
            .min = if (obj.get("min")) |min_val| try parseF64Array(allocator, min_val.array) else null,
            .max = if (obj.get("max")) |max_val| try parseF64Array(allocator, max_val.array) else null,
        };
    }

    return accessors;
}

fn parseBufferViews(allocator: Allocator, arr: json.Array) ![]BufferView {
    var buffer_views = try allocator.alloc(BufferView, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        buffer_views[i] = BufferView{
            .name = if (obj.get("name")) |n| n.string else null,
            .buffer = @intCast(obj.get("buffer").?.integer),
            .byte_offset = if (obj.get("byteOffset")) |bo| @intCast(bo.integer) else 0,
            .byte_length = @intCast(obj.get("byteLength").?.integer),
            .byte_stride = if (obj.get("byteStride")) |bs| @intCast(bs.integer) else null,
            .target = if (obj.get("target")) |t| @intCast(t.integer) else null,
        };
    }

    return buffer_views;
}

fn parseBuffers(allocator: Allocator, arr: json.Array) ![]Buffer {
    var buffers = try allocator.alloc(Buffer, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;
        buffers[i] = Buffer{
            .name = if (obj.get("name")) |n| n.string else null,
            .byte_length = @intCast(obj.get("byteLength").?.integer),
            .uri = if (obj.get("uri")) |u| u.string else null,
        };
    }

    return buffers;
}

fn parseAnimations(allocator: Allocator, arr: json.Array) ![]Animation {
    var animations = try allocator.alloc(Animation, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;

        const channels_arr = obj.get("channels").?.array;
        var channels = try allocator.alloc(Animation.Channel, channels_arr.items.len);

        for (channels_arr.items, 0..) |ch_item, j| {
            const ch_obj = ch_item.object;
            const target_obj = ch_obj.get("target").?.object;

            channels[j] = Animation.Channel{
                .sampler = @intCast(ch_obj.get("sampler").?.integer),
                .target = Animation.Channel.Target{
                    .node = if (target_obj.get("node")) |n| @intCast(n.integer) else null,
                    .path = target_obj.get("path").?.string,
                },
            };
        }

        const samplers_arr = obj.get("samplers").?.array;
        var samplers = try allocator.alloc(Animation.AnimationSampler, samplers_arr.items.len);

        for (samplers_arr.items, 0..) |samp_item, j| {
            const samp_obj = samp_item.object;
            samplers[j] = Animation.AnimationSampler{
                .input = @intCast(samp_obj.get("input").?.integer),
                .output = @intCast(samp_obj.get("output").?.integer),
                .interpolation = if (samp_obj.get("interpolation")) |interp| interp.string else "LINEAR",
            };
        }

        animations[i] = Animation{
            .channels = channels,
            .samplers = samplers,
            .name = if (obj.get("name")) |n| n.string else null,
        };
    }

    return animations;
}

fn parseSkins(allocator: Allocator, arr: json.Array) ![]Skin {
    var skins = try allocator.alloc(Skin, arr.items.len);

    for (arr.items, 0..) |item, i| {
        const obj = item.object;

        skins[i] = Skin{
            .name = if (obj.get("name")) |n| n.string else null,
            .inverse_bind_matrices = if (obj.get("inverseBindMatrices")) |ibm| @intCast(ibm.integer) else null,
            .skeleton = if (obj.get("skeleton")) |s| @intCast(s.integer) else null,
            .joints = try parseU32Array(allocator, obj.get("joints").?.array),
        };
    }

    return skins;
}

// Utility functions
fn parseU32Array(allocator: Allocator, arr: json.Array) ![]u32 {
    var result = try allocator.alloc(u32, arr.items.len);
    for (arr.items, 0..) |item, i| {
        result[i] = @intCast(item.integer);
    }
    return result;
}

fn parseF64Array(allocator: Allocator, arr: json.Array) ![]f64 {
    var result = try allocator.alloc(f64, arr.items.len);
    for (arr.items, 0..) |item, i| {
        result[i] = item.float;
    }
    return result;
}
