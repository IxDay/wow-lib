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

    pub fn init(allocator: std.mem.Allocator, object: json.ObjectMap) !Asset {
        const version = object.get("version") orelse return error.MissingVersion;

        return Asset{
            .version = try allocator.dupe(u8, version.string),
            .generator = try parseString(allocator, object.get("generator")),
            .min_version = try parseString(allocator, object.get("minVersion")),
            .copyright = try parseString(allocator, object.get("copyright")),
        };
    }
};

// Buffer - raw binary data
pub const Buffer = struct {
    byte_length: u32,
    uri: ?[]const u8 = null,
    name: ?[]const u8 = null,

    pub fn deinit(self: Buffer, allocator: Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.uri) |uri| allocator.free(uri);
    }
};

// BufferView - chunk of buffer data
pub const BufferView = struct {
    buffer: u32,
    byte_offset: u32 = 0,
    byte_length: u32,
    byte_stride: ?u32 = null,
    target: ?u32 = null,
    name: ?[]const u8 = null,

    pub fn deinit(self: BufferView, allocator: Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
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

    pub fn deinit(self: Accessor, allocator: Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
};

// Image
pub const Image = struct {
    uri: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
    buffer_view: ?u32 = null,
    name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, object: std.json.ObjectMap) !Image {
        return Image{
            .name = try parseString(allocator, object.get("name")),
            .uri = try parseString(allocator, object.get("uri")),
            .mime_type = try parseString(allocator, object.get("mimeType")),
            .buffer_view = try parseU32(object.get("bufferView")),
        };
    }

    pub fn deinit(self: Image, allocator: Allocator) void {
        if (self.uri) |uri| allocator.free(uri);
        if (self.mime_type) |mime_type| allocator.free(mime_type);
        if (self.name) |name| allocator.free(name);
    }
};

// Sampler
pub const Sampler = struct {
    mag_filter: ?u32 = null,
    min_filter: ?u32 = null,
    wrap_s: u32 = 10497, // GL_REPEAT
    wrap_t: u32 = 10497, // GL_REPEAT
    name: ?[]const u8 = null,

    pub fn deinit(self: Sampler, allocator: Allocator) void {
        if (self.name) |name| allocator.free(name);
    }

    pub fn init(allocator: Allocator, object: json.ObjectMap) !Sampler {
        return Sampler{
            .name = try parseString(allocator, object.get("name")),
            .mag_filter = try parseU32(object.get("magFilter")),
            .min_filter = try parseU32(object.get("minFilter")),
            .wrap_s = try parseU32(object.get("wrapS")) orelse 10497,
            .wrap_t = try parseU32(object.get("wrapT")) orelse 10497,
        };
    }
};

// Texture
pub const Texture = struct {
    sampler: ?u32 = null,
    source: ?u32 = null,
    name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, object: std.json.ObjectMap) !Texture {
        return Texture{
            .name = try parseString(allocator, object.get("name")),
            .sampler = if (object.get("sampler")) |s| @intCast(s.integer) else null,
            .source = if (object.get("source")) |s| @intCast(s.integer) else null,
        };
    }

    pub fn deinit(self: Texture, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
};

const Error = error{
    InvalidType,
};

pub fn cast(value: std.json.Value) !f64 {
    return switch (value) {
        .float => |float| float,
        .integer => |integer| @as(f64, @floatFromInt(integer)),
        else => Error.InvalidType,
    };
}

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

    pub fn init(allocator: std.mem.Allocator, object: std.json.ObjectMap) !Material {
        var material = Material{
            .name = try parseString(allocator, object.get("name")),
            .alpha_mode = if (object.get("alphaMode")) |am| am.string else "OPAQUE",
            .alpha_cutoff = if (object.get("alphaCutoff")) |ac| ac.float else 0.5,
            .double_sided = if (object.get("doubleSided")) |ds| ds.bool else false,
        };

        // Parse emissive factor
        if (object.get("emissiveFactor")) |ef| {
            const ef_arr = ef.array;
            material.emissive_factor = [_]f64{
                ef_arr.items[0].float,
                ef_arr.items[1].float,
                ef_arr.items[2].float,
            };
        }

        return material;
    }

    pub fn deinit(self: Material, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
};

// Mesh primitive
pub const Primitive = struct {
    attributes: std.StringHashMap(u32),
    indices: ?u32 = null,
    material: ?u32 = null,
    mode: PrimitiveMode = .triangles,
    targets: ?[]std.StringHashMap(u32) = null,

    pub fn deinit(self: Primitive, allocator: std.mem.Allocator) void {
        var attributes_iterator = self.attributes.iterator();
        while (attributes_iterator.next()) |entry| allocator.free(entry.key_ptr.*);

        @constCast(&self.attributes).deinit();
        if (self.targets) |targets| {
            for (targets) |target| {
                var target_iterator = target.iterator();
                while (target_iterator.next()) |entry| allocator.free(entry.key_ptr.*);
                @constCast(&target).deinit();
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator, object: json.ObjectMap) !Primitive {
        // Parse attributes
        var attributes = std.StringHashMap(u32).init(allocator);
        if (object.get("attributes")) |attrs_val| {
            var attrs_iter = attrs_val.object.iterator();
            while (attrs_iter.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                try attributes.put(key, @intCast(entry.value_ptr.integer));
            }
        }

        return Primitive{
            .attributes = attributes,
            .indices = if (object.get("indices")) |idx| @intCast(idx.integer) else null,
            .material = if (object.get("material")) |mat| @intCast(mat.integer) else null,
            .mode = if (object.get("mode")) |mode| @enumFromInt(mode.integer) else .triangles,
        };
    }
};

// Mesh
pub const Mesh = struct {
    primitives: []Primitive,
    weights: ?[]f64 = null,
    name: ?[]const u8 = null,

    pub fn deinit(self: Mesh, allocator: std.mem.Allocator) void {
        for (self.primitives) |primitive| primitive.deinit(allocator);
        allocator.free(self.primitives);

        if (self.name) |name| allocator.free(name);
    }
    pub fn init(allocator: std.mem.Allocator, object: json.ObjectMap) !Mesh {
        const primitives_arr = object.get("primitives").?.array;

        var primitives = try allocator.alloc(Primitive, primitives_arr.items.len);

        for (primitives_arr.items, 0..) |prim_item, j| {
            primitives[j] = try Primitive.init(allocator, prim_item.object);
        }
        return Mesh{
            .primitives = primitives,
            .name = if (object.get("name")) |n| try allocator.dupe(u8, n.string) else null,
        };
    }
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

    pub fn deinit(self: Node, allocator: std.mem.Allocator) void {
        if (self.children) |children| allocator.free(children);
        if (self.weights) |weights| allocator.free(weights);
        if (self.name) |name| allocator.free(name);
    }

    pub fn init(allocator: std.mem.Allocator, object: std.json.ObjectMap) !Node {
        var node = Node{
            .name = try parseString(allocator, object.get("name")),
            .mesh = if (object.get("mesh")) |m| @intCast(m.integer) else null,
            .children = try parseU32Array(allocator, object.get("children")),
        };

        // Parse optional transform arrays
        if (object.get("translation")) |t| {
            const trans_arr = t.array;
            node.translation = [_]f64{
                try cast(trans_arr.items[0]),
                try cast(trans_arr.items[1]),
                try cast(trans_arr.items[2]),
            };
        }

        if (object.get("rotation")) |r| {
            const rot_arr = r.array;
            node.rotation = [_]f64{
                try cast(rot_arr.items[0]),
                try cast(rot_arr.items[1]),
                try cast(rot_arr.items[2]),
                try cast(rot_arr.items[3]),
            };
        }

        if (object.get("scale")) |s| {
            const scale_arr = s.array;
            node.scale = [_]f64{
                try cast(scale_arr.items[0]),
                try cast(scale_arr.items[1]),
                try cast(scale_arr.items[2]),
            };
        }

        if (object.get("matrix")) |m| {
            const matrix_arr = m.array;
            for (0..16) |j| {
                node.matrix.?[j] = try cast(matrix_arr.items[j]);
            }
        }
        return node;
    }
};

// Scene
pub const Scene = struct {
    nodes: ?[]u32 = null,
    name: ?[]const u8 = null,

    pub fn deinit(self: Scene, allocator: std.mem.Allocator) void {
        if (self.nodes) |nodes| allocator.free(nodes);
        if (self.name) |name| allocator.free(name);
    }

    pub fn init(allocator: std.mem.Allocator, object: json.ObjectMap) !Scene {
        return Scene{
            .name = try parseString(allocator, object.get("name")),
            .nodes = try parseU32Array(allocator, object.get("nodes")),
        };
    }
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

        pub fn deinit(self: Channel, allocator: Allocator) void {
            allocator.free(self.target.path);
        }
    };

    pub const AnimationSampler = struct {
        input: u32,
        interpolation: []const u8 = "LINEAR",
        output: u32,
    };

    pub fn deinit(self: Animation, allocator: Allocator) void {
        for (self.channels) |channel| channel.deinit(allocator);
        if (self.name) |name| allocator.free(name);
    }
};

// Skin
pub const Skin = struct {
    inverse_bind_matrices: ?u32 = null,
    skeleton: ?u32 = null,
    joints: []u32,
    name: ?[]const u8 = null,

    pub fn deinit(self: Skin, allocator: Allocator) void {
        if (self.name) |name| allocator.free(name);
    }
};

// Main glTF structure
pub const Gltf = struct {
    asset: Asset,
    scene: ?u32 = null,
    scenes: ?[]Scene = null,
    nodes: ?[]Node = null,
    meshes: ?[]Mesh = null,
    materials: ?[]Material = null,
    textures: ?[]Texture = null,
    images: ?[]Image = null,
    samplers: ?[]Sampler = null,
    accessors: ?[]Accessor = null,
    buffer_views: ?[]BufferView = null,
    buffers: ?[]Buffer = null,
    animations: ?[]Animation = null,
    skins: ?[]Skin = null,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: Allocator) void {
        const free = struct {
            allocator: Allocator,
            fn call(this: *const @This(), comptime T: type, array: ?[]T) void {
                if (!@hasDecl(T, "deinit")) {
                    @compileError("Type " ++ @typeName(T) ++ " must have a deinit() method");
                }
                const arr = array orelse return;

                for (arr) |*elem| {
                    elem.deinit(this.allocator);
                }
                this.allocator.free(arr);
            }
        }{ .allocator = allocator };

        self.asset.deinit(allocator);

        free.call(Scene, self.scenes);
        free.call(Node, self.nodes);
        free.call(Mesh, self.meshes);
        free.call(Material, self.materials);
        free.call(Texture, self.textures);
        free.call(Image, self.images);
        free.call(Sampler, self.samplers);
        free.call(Accessor, self.accessors);
        free.call(BufferView, self.buffer_views);
        free.call(Buffer, self.buffers);
        free.call(Animation, self.animations);
        free.call(Skin, self.skins);
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
        const asset = try Asset.init(allocator, asset_obj.object);

        var gltf = Self{
            .asset = asset,
        };
        // Parse optional fields
        if (root.get("scene")) |scene_val| {
            gltf.scene = @intCast(scene_val.integer);
        }

        const alloc = struct {
            allocator: Allocator,
            fn call(this: *const @This(), comptime T: type, value: ?json.Value) !?[]T {
                if (!@hasDecl(T, "init")) {
                    @compileError("Type " ++ @typeName(T) ++ " must have a init() method");
                }
                const items = if (value) |v| v.array.items else return null;
                const out = try this.allocator.alloc(T, items.len);

                for (items, 0..) |item, i| {
                    out[i] = try T.init(this.allocator, item.object);
                }
                return out;
            }
        }{ .allocator = allocator };

        gltf.scenes = try alloc.call(Scene, root.get("scenes"));
        gltf.nodes = try alloc.call(Node, root.get("nodes"));
        gltf.meshes = try alloc.call(Mesh, root.get("meshes"));
        gltf.materials = try alloc.call(Material, root.get("materials"));
        gltf.textures = try alloc.call(Texture, root.get("textures"));
        gltf.images = try alloc.call(Image, root.get("images"));
        gltf.samplers = try alloc.call(Sampler, root.get("samplers"));

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
            .min = try parseF64Array(allocator, obj.get("min")) orelse null,
            .max = try parseF64Array(allocator, obj.get("max")) orelse null,
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
fn parseU32Array(allocator: Allocator, value: ?json.Value) !?[]u32 {
    return ArrayParser(u32).init(value).parse(allocator);
}

fn parseF64Array(allocator: Allocator, value: ?json.Object) !?[]f64 {
    if (!value or value.array) return null;
    const items = value.array.?.items;
    var result = try allocator.alloc(f64, items.len);
    for (items, 0..) |item, i| {
        result[i] = item.float;
    }
    return result;
}

fn parseString(allocator: Allocator, value: ?std.json.Value) !?[]const u8 {
    return ArrayParser(u8).init(value).parse(allocator);
}

fn parseU32(value: ?std.json.Value) !?u32 {
    return Parser(u32).init(value).parse();
}

fn ArrayParser(comptime T: type) type {
    return struct {
        value: ?std.json.Value,
        const Self = @This();

        pub fn init(value: ?json.Value) Self {
            return Self{ .value = value };
        }

        pub fn parse(self: Self, allocator: Allocator) !?[]T {
            const value = self.value orelse return null;
            switch (value) {
                .string, .number_string => |s| {
                    if (T != u8) return Error.InvalidType;
                    return try allocator.dupe(u8, s);
                },
                .array => |array| {
                    const out = try allocator.alloc(T, array.items.len);
                    for (array.items, 0..) |item, i| out[i] = try parseItem(item);
                    return out;
                },
                else => return Error.InvalidType,
            }
        }

        fn parseItem(item: json.Value) !T {
            return switch (@typeInfo(T)) {
                .int, .comptime_int => switch (item) {
                    .integer => |i| @as(T, @intCast(i)),
                    .float => |f| @as(T, @intFromFloat(f)),
                    else => Error.InvalidType,
                },
                .float, .comptime_float => switch (item) {
                    .float => |f| @as(T, @floatCast(f)),
                    else => Error.InvalidType,
                },
                else => Error.InvalidType,
            };
        }
    };
}

fn Parser(comptime T: type) type {
    return struct {
        value: ?std.json.Value,

        const Self = @This();

        pub fn init(value: ?std.json.Value) Self {
            return Self{ .value = value };
        }

        pub fn parse(self: Self) !?T {
            const value = self.value orelse return null;
            return switch (T) {
                u32 => @intCast(value.integer),
                else => Error.InvalidType,
            };
        }
    };
}
