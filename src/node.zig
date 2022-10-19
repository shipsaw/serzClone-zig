const std = @import("std");
// const keywords = std.StringHashMap(dataType).init(allocator);

pub const dataType = enum {
    _bool,
    _sUInt8,
    _sInt32,
    _sUInt64,
    _sFloat32,
    _cDeltaString,
};

pub const dataUnion = union(dataType) {
    _bool: bool,
    _sUInt8: u8,
    _sInt32: i32,
    _sUInt64: u64,
    _sFloat32: f32,
    _cDeltaString: []const u8,
};

pub const ff41node = struct {
    name: []const u8,
    numElements: u8,
    dType: dataType,
    values: std.ArrayList(dataUnion),
};

pub const ff4enode = struct {};

pub const ff50node = struct {
    name: []const u8,
    id: u32,
    numChildren: u32,
    children: std.ArrayList(node),
};

pub const ff56node = struct {
    name: []const u8,
    dType: dataType,
    value: dataUnion,
};

pub const ff70node = struct {
    name: []const u8,
};

pub const node = union(enum) {
    ff41node: ff41node,
    ff4enode: ff4enode,
    ff50node: ff50node,
    ff56node: ff56node,
    ff70node: ff70node,
};
