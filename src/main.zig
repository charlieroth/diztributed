const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const json = std.json;
const crypto = std.crypto;
const fmt = std.fmt;
const assert = std.debug.assert;

const encoded_pos = [16]u8{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };

const hex_to_nibble = [256]u8{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};

pub fn newId() []u8 {
    // seed bytes
    var bytes: [16]u8 = .{0} ** 16;
    crypto.random.bytes(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[1] = (bytes[8] & 0x3f) | 0x80;

    // craft uuid
    var buf: [36]u8 = undefined;
    const hex = "0123456789abcdef";
    buf[8] = '-';
    buf[13] = '-';
    buf[18] = '-';
    buf[23] = '-';
    inline for (encoded_pos, 0..) |i, j| {
        buf[i + 0] = hex[bytes[j] >> 4];
        buf[i + 1] = hex[bytes[j] & 0x0f];
    }

    return buf[0..];
}

const MsgParseError = error{Unknown};

const MsgType = enum { Init, Echo, Generate };

const Node = struct {
    id: ?[]const u8 = null,
};

fn Msg(comptime T: type) type {
    return struct {
        id: u8,
        src: []const u8,
        dest: []const u8,
        body: T,
    };
}

const Init = struct {
    type: []const u8,
    msg_id: u8,
    node_id: []const u8,
    node_ids: [][]const u8,
};

const InitReply = struct {
    type: []const u8,
    in_reply_to: u8,
};

const Echo = struct {
    type: []const u8,
    msg_id: u8,
    echo: []const u8,
};

const EchoReply = struct {
    type: []const u8,
    msg_id: ?u8,
    echo: []const u8,
    in_reply_to: u8,
};

const Generate = struct {
    type: []const u8,
    msg_id: u8,
};

const GenerateReply = struct {
    type: []const u8,
    id: []const u8,
    in_reply_to: u8,
};

fn getMsgType(msgBodyType: []const u8) MsgParseError!MsgType {
    if (mem.eql(u8, msgBodyType, "init")) {
        return MsgType.Init;
    } else if (mem.eql(u8, msgBodyType, "echo")) {
        return MsgType.Echo;
    } else if (mem.eql(u8, msgBodyType, "generate")) {
        return MsgType.Generate;
    } else {
        return MsgParseError.Unknown;
    }
}

fn parseInitMessage(allocator: mem.Allocator, msg: []const u8) !*Msg(Init) {
    var stream: json.TokenStream = json.TokenStream.init(msg);
    var data: Msg(Init) = try json.parse(Msg(Init), &stream, .{ .allocator = allocator });
    return &data;
}

fn handleInitMessage(msg: Msg(Init), node: *Node) Msg(InitReply) {
    return Msg(InitReply){
        .id = msg.id,
        .src = node.id.?[0..],
        .dest = msg.src,
        .body = InitReply{
            .type = "init_ok",
            .in_reply_to = msg.body.msg_id,
        },
    };
}

fn parseEchoMessage(allocator: mem.Allocator, msg: []u8) !Msg(Echo) {
    var stream: json.TokenStream = json.TokenStream.init(msg);
    var data: Msg(Echo) = try json.parse(Msg(Echo), &stream, .{ .allocator = allocator });
    return data;
}

fn handleEchoMessage(msg: Msg(Echo), node: *Node) Msg(EchoReply) {
    return Msg(EchoReply){
        .id = msg.id,
        .src = node.id.?,
        .dest = msg.src,
        .body = EchoReply{
            .type = "echo_ok",
            .msg_id = msg.body.msg_id,
            .echo = msg.body.echo,
            .in_reply_to = msg.body.msg_id,
        },
    };
}

fn parseGenerateMessage(allocator: mem.Allocator, msg: []u8) !Msg(Generate) {
    var stream: json.TokenStream = json.TokenStream.init(msg);
    const data: Msg(Generate) = try json.parse(Msg(Generate), &stream, .{ .allocator = allocator });
    return data;
}

fn handleGenerateMessage(msg: Msg(Generate), id: []const u8, node: *Node) Msg(GenerateReply) {
    return Msg(GenerateReply){
        .id = msg.id,
        .src = node.id.?,
        .dest = msg.src,
        .body = GenerateReply{
            .type = "generate_ok",
            .id = id,
            .in_reply_to = msg.body.msg_id,
        },
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // defer {
    //     const didLeak = gpa.deinit();
    //     assert(!didLeak);
    // }

    var allocator = gpa.allocator();
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var node = Node{};

    while (true) {
        if (try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 400)) |msg| {
            // Parse incoming message (dynamically)
            var parser = json.Parser.init(allocator, false);
            var tree = try parser.parse(msg[0..]);

            // Determine message type
            const body = tree.root.Object.get("body");
            const msgBodyType: []const u8 = body.?.Object.get("type").?.String;
            const msgType = try getMsgType(msgBodyType);

            if (msgType == .Init) {
                var stream = json.TokenStream.init(msg[0..]);
                const msgData = try json.parse(Msg(Init), &stream, .{ .allocator = allocator });
                const replyMsg = handleInitMessage(msgData, &node);
                const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
                try stdout.print("{s}\n", .{reply});
                json.parseFree(Msg(Init), msgData, .{ .allocator = allocator });
                allocator.free(reply);
            } else if (msgType == .Echo) {
                var stream = json.TokenStream.init(msg[0..]);
                const msgData = try json.parse(Msg(Echo), &stream, .{ .allocator = allocator });
                const replyMsg = handleEchoMessage(msgData, node.id.?[0..]);
                const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
                try stdout.print("{s}\n", .{reply});
                json.parseFree(Msg(Echo), msgData, .{ .allocator = allocator });
                allocator.free(reply);
            } else if (msgType == .Generate) {
                var stream = json.TokenStream.init(msg[0..]);
                const msgData = try json.parse(Msg(Generate), &stream, .{ .allocator = allocator });
                const idBuf = newId();
                const id = try std.fmt.allocPrint(allocator, "{s}", .{idBuf});
                const replyMsg = handleGenerateMessage(msgData, id[0..], &node);
                const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
                try stdout.print("{s}\n", .{reply});
                json.parseFree(Msg(Generate), msgData, .{ .allocator = allocator });
                allocator.free(reply);
                allocator.free(id);
            } else {
                std.debug.print("You fucked up\n", .{});
            }

            parser.deinit();
            tree.deinit();
            allocator.free(msg);
        }
    }
}

// const initMsg: []const u8 =
//     \\ {"id": 0, "src": "c1", "dest": "n1", "body": {"type": "init", "msg_id": 1, "node_id": "n1", "node_ids": ["n1", "n2", "n3"]}}
// ;

// const echoMsg: []const u8 =
//     \\ {"id": 1, "src": "c1", "dest": "n1", "body": {"type": "echo", "msg_id": 1, "echo": "Please echo 35"}}
// ;

const generateMsg: []const u8 =
    \\ {"id": 1, "src": "c1", "dest": "n1", "body": {"type": "generate", "msg_id": 1}}
;

// test "full init message lifecycle" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//
//     var node: Node = Node{};
//
//     var parser = json.Parser.init(allocator, false);
//     var tree = try parser.parse(initMsg);
//
//     const body = tree.root.Object.get("body");
//     const msgBodyType: []const u8 = body.?.Object.get("type").?.String;
//     std.debug.print("message body type: {s}\n", .{msgBodyType});
//
//     _ = try getMsgType(msgBodyType);
//
//     var stream: json.TokenStream = json.TokenStream.init(initMsg);
//     const msgData = try json.parse(Msg(Init), &stream, .{ .allocator = allocator });
//
//     const replyMsg: Msg(InitReply) = handleInitMessage(msgData, &node);
//
//     const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
//     std.debug.print("reply: {s}\n", .{reply});
//
//     parser.deinit();
//     tree.deinit();
//     json.parseFree(Msg(Init), msgData, .{ .allocator = allocator });
//     allocator.free(reply);
//
//     const didLeak = gpa.deinit();
//     try testing.expect(!didLeak);
// }

test "full echo message lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var echoMsg =
        \\ {"id": 1, "src": "c1", "dest": "n1", "body": {"type": "echo", "msg_id": 1, "echo": "Please echo 35"}}
    ;

    var node: Node = Node{ .id = "n1" };
    // ---- Echo Message Start ----
    var parser = json.Parser.init(allocator, false);
    var tree = try parser.parse(echoMsg[0..]);
    const body = tree.root.Object.get("body");
    const msgBodyType = body.?.Object.get("type").?.String;
    std.debug.print("message body type: {s}\n", .{msgBodyType});
    _ = try getMsgType(msgBodyType);
    var stream = json.TokenStream.init(echoMsg[0..]);
    const msgData = try json.parse(Msg(Echo), &stream, .{ .allocator = allocator });
    std.debug.print("msgData.src: {s}\n", .{msgData.src});
    std.debug.print("msgData.dest: {s}\n", .{msgData.dest});
    std.debug.print("msgData.body.type: {s}\n", .{msgData.body.type});
    std.debug.print("msgData.body.echo: {s}\n", .{msgData.body.echo});
    const replyMsg = handleEchoMessage(msgData, &node);
    const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
    std.debug.print("echo reply: {s}\n", .{reply});
    // Free Memory
    json.parseFree(Msg(Echo), msgData, .{ .allocator = allocator });
    allocator.free(reply);
    parser.deinit();
    tree.deinit();

    const didLeak = gpa.deinit();
    try testing.expect(!didLeak);
}

// test "full generate message lifecycle" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//
//     var node: Node = Node{ .id = "n0" };
//
//     var parser = json.Parser.init(allocator, false);
//     var tree = try parser.parse(generateMsg);
//
//     const body = tree.root.Object.get("body");
//     const msgBodyType: []const u8 = body.?.Object.get("type").?.String;
//     std.debug.print("message body type: {s}\n", .{msgBodyType});
//
//     _ = try getMsgType(msgBodyType);
//
//     var stream: json.TokenStream = json.TokenStream.init(generateMsg);
//     const msgData = try json.parse(Msg(Generate), &stream, .{ .allocator = allocator });
//
//     const idBuf: []u8 = newId();
//     const id = try std.fmt.allocPrint(allocator, "{s}", .{idBuf});
//     const replyMsg: Msg(GenerateReply) = handleGenerateMessage(msgData, id[0..], &node);
//
//     const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
//     std.debug.print("reply: {s}\n", .{reply});
//
//     parser.deinit();
//     tree.deinit();
//     json.parseFree(Msg(Generate), msgData, .{ .allocator = allocator });
//     allocator.free(reply);
//     allocator.free(id);
//
//     const didLeak = gpa.deinit();
//     try testing.expect(!didLeak);
// }
