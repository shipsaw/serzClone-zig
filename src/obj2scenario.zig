const std = @import("std");
const parser = @import("bin2obj.zig");
const json = @import("custom_json.zig");
const n = @import("node.zig");
const sm = @import("scenarioModel.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const status = struct {
    nodeList: []const n.node,
    current: usize,

    pub fn init(nodes: []const n.node) status {
        return status{
            .nodeList = nodes,
            .current = 0,
        };
    }
};

pub fn parse(nodes: []const n.node) ![]const u8 {
    const scenarioModelObj = try buildModel(nodes);
    var string = std.ArrayList(u8).init(allocator);
    try json.stringify(scenarioModelObj, .{}, string.writer());
    return string.items;
}

fn buildModel(nodes: []const n.node) sm.cRecordSet {
    _ = nodes;
    return undefined;
}

fn parse_sTimeOfDay(s: *status) sm.sTimeOfDay {
    const hour = s.nodeList[s.current + 1].ff56node.value._sInt32;
    const minute = s.nodeList[s.current + 2].ff56node.value._sInt32;
    const second = s.nodeList[s.current + 3].ff56node.value._sInt32;
    s.current += 4;
    return sm.sTimeOfDay{
        ._iHour = hour,
        ._iMinute = minute,
        ._iSeconds = second,
    };
}

fn parse_parseLocalisation_cUserLocalisedString(s: *status) !sm.Localisation_cUserLocalisedString {
    // <English d:type="cDeltaString">6C58 10:45 Heathfield-St Blazey S.S</English>
    // <French d:type="cDeltaString"></French>
    // <Italian d:type="cDeltaString"></Italian>
    // <German d:type="cDeltaString"></German>
    // <Spanish d:type="cDeltaString"></Spanish>
    // <Dutch d:type="cDeltaString"></Dutch>
    // <Polish d:type="cDeltaString"></Polish>
    // <Russian d:type="cDeltaString"></Russian>
    // <Other/>
    // <Key d:type="cDeltaString">3c129cec-eef3-48a9-9fbb-05c5ab331e05</Key>

    const english = s.nodeList[s.current + 1].ff56node.value._cDeltaString;
    const french = s.nodeList[s.current + 2].ff56node.value._cDeltaString;
    const italian = s.nodeList[s.current + 3].ff56node.value._cDeltaString;
    const german = s.nodeList[s.current + 4].ff56node.value._cDeltaString;
    const spanish = s.nodeList[s.current + 5].ff56node.value._cDeltaString;
    const dutch = s.nodeList[s.current + 6].ff56node.value._cDeltaString;
    const polish = s.nodeList[s.current + 7].ff56node.value._cDeltaString;
    const russian = s.nodeList[s.current + 8].ff56node.value._cDeltaString;

    var otherList = std.ArrayList(sm.Localization_otherLanguage).init(allocator);
    const otherListLen = s.nodeList[s.current + 9].ff50node.children;

    var i: u32 = 0;
    while (i < otherListLen) : (i += 1) {
        const tempNode = sm.Localization_otherLanguage{
            .LangName = s.nodeList[s.current + 10 + i].ff56node.name,
            .Value = s.nodeList[s.current + 10 + i].ff56node.value._cDeltaString,
        };
        try otherList.append(tempNode);
    }
    const key = s.nodeList[s.current + 10 + otherListLen].ff56node.value._cDeltaString;
    s.current += 11 + otherListLen;

    return sm.Localisation_cUserLocalisedString{
        .English = english,
        .French = french,
        .Italian = italian,
        .German = german,
        .Spanish = spanish,
        .Dutch = dutch,
        .Polish = polish,
        .Russian = russian,
        .Other = otherList.items,
        .Key = key,
    };
}

////////////////////////////////////////////////////////////
/////////////////// Test Area //////////////////////////////
////////////////////////////////////////////////////////////

test "Parse Time of Day" {
    // Arrange
    const parentNode = n.node{ .ff50node = n.ff50node{
        .name = "sTimeOfDay",
        .id = 0,
        .children = 3,
    } };
    const hourNode = n.node{ .ff56node = n.ff56node{
        .name = "_iHour",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 1 },
    } };
    const minuteNode = n.node{ .ff56node = n.ff56node{
        .name = "_iMinute",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 3 },
    } };
    const secondNode = n.node{ .ff56node = n.ff56node{
        .name = "_iSeconds",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 5 },
    } };
    const nodeList = &[_]n.node{ parentNode, hourNode, minuteNode, secondNode };
    var s = status.init(nodeList);

    // Act
    const result = parse_sTimeOfDay(&s);

    // Assert
    try expectEqual(result._iHour, 1);
    try expectEqual(result._iMinute, 3);
    try expectEqual(result._iSeconds, 5);
    try expectEqual(s.current, 4);
}

test "Parse Localization_cUserLocalizedString" {
    // Arrange
    const parentNode = n.node{ .ff50node = n.ff50node{
        .name = "cUserLocalizedString",
        .id = 0,
        .children = 10,
    } };
    const english = n.node{ .ff56node = n.ff56node{
        .name = "English",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "English String" },
    } };
    const french = n.node{ .ff56node = n.ff56node{
        .name = "French",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const italian = n.node{ .ff56node = n.ff56node{
        .name = "Italian",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const german = n.node{ .ff56node = n.ff56node{
        .name = "German",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const spanish = n.node{ .ff56node = n.ff56node{
        .name = "Spanish",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const dutch = n.node{ .ff56node = n.ff56node{
        .name = "Dutch",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const polish = n.node{ .ff56node = n.ff56node{
        .name = "Polish",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const russian = n.node{ .ff56node = n.ff56node{
        .name = "Russian",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const other = n.node{ .ff50node = n.ff50node{
        .name = "Other",
        .id = 0,
        .children = 1,
    } };
    const chinese = n.node{ .ff56node = n.ff56node{
        .name = "Chinese",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "How" },
    } };
    const key = n.node{ .ff56node = n.ff56node{
        .name = "English",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "KEY VAL" },
    } };
    const nodeList = &[_]n.node{ parentNode, english, french, italian, german, spanish, dutch, polish, russian, other, chinese, key };
    var s = status.init(nodeList);

    // Act
    const result = try parse_parseLocalisation_cUserLocalisedString(&s);

    // Assert
    try expectEqualStrings(result.English, "English String");
    try expectEqualStrings(result.Italian, "");
    try expectEqualStrings(result.Key, "KEY VAL");
    try expectEqualStrings(result.Other[0].Value, "How");
    try expectEqual(s.current, 12);
}
