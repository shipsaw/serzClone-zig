const std = @import("std");
// const keywords = std.StringHashMap(dataType).init(allocator);

pub const dataType = enum {
    _bool,
    _sUInt8,
    _sInt16,
    _sInt32,
    _sUInt32,
    _sUInt64,
    _sFloat32,
    _cDeltaString,
};

pub const dataTypeMap = std.ComptimeStringMap(dataType, .{
    .{ "bool", ._bool },
    .{ "sUInt8", ._sUInt8 },
    .{ "sInt16", ._sInt16 },
    .{ "sInt32", ._sInt32 },
    .{ "sUInt32", ._sUInt32 },
    .{ "sUInt64", ._sUInt64 },
    .{ "sFloat32", ._sFloat32 },
    .{ "cDeltaString", ._cDeltaString },
});

pub const dataUnion = union(dataType) {
    _bool: bool,
    _sUInt8: u8,
    _sInt16: i16,
    _sInt32: i32,
    _sUInt32: u32,
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
    children: u32,
};

pub const ff52node = struct {
    name: []const u8,
    value: u32,
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
    ff52node: ff52node,
    ff56node: ff56node,
    ff70node: ff70node,
};

pub const textNode = union(enum) {
    ff41NodeT: ff41NodeT,
    ff4eNodeT: ff4eNodeT,
    ff50NodeT: ff50NodeT,
    ff52NodeT: ff52NodeT,
    ff56NodeT: ff56NodeT,
    ff70NodeT: ff70NodeT,
};

pub const ff41NodeT = struct {
    name: []const u8,
    numElements: u8,
    dType: []const u8,
    values: []dataUnion,
};

pub const ff4eNodeT = struct {};

pub const ff50NodeT = struct {
    name: []const u8,
    id: u32,
    children: []textNode,
};

pub const ff52NodeT = struct {
    name: []const u8,
    value: u32,
};

pub const ff56NodeT = struct {
    name: []const u8,
    dType: []const u8,
    value: dataUnion,
};

pub const ff70NodeT = struct {
    name: []const u8,
};
