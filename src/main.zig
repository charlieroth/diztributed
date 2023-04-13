const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const json = std.json;

const MsgParseError = error{Unknown};

const MsgType = enum { Init, Echo };

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

fn getMsgType(allocator: mem.Allocator, msg: []const u8) !MsgType {
    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(msg);
    defer tree.deinit();

    const body = tree.root.Object.get("body");
    const bodyType = body.?.Object.get("type").?.String;

    if (mem.eql(u8, bodyType, "init")) {
        return MsgType.Init;
    } else if (mem.eql(u8, bodyType, "echo")) {
        return MsgType.Echo;
    } else {
        return MsgParseError.Unknown;
    }
}

fn parseInitMessage(allocator: mem.Allocator, msg: []const u8) !Msg(Init) {
    var stream: json.TokenStream = json.TokenStream.init(msg);
    var data: Msg(Init) = try json.parse(Msg(Init), &stream, .{ .allocator = allocator });
    return data;
}

fn parseEchoMessage(allocator: mem.Allocator, msg: []const u8) !Msg(Echo) {
    var stream: json.TokenStream = json.TokenStream.init(msg);
    var data: Msg(Echo) = try json.parse(Msg(Echo), &stream, .{ .allocator = allocator });
    return data;
}

fn handleInitMessage(msg: Msg(Init), node: *Node) Msg(InitReply) {
    node.id = msg.body.node_id;
    return Msg(InitReply){
        .id = msg.id,
        .src = node.id.?,
        .dest = msg.src,
        .body = InitReply{
            .type = "init_ok",
            .in_reply_to = msg.body.msg_id,
        },
    };
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var node = Node{};

    while (true) {
        if (try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1000)) |msg| {
            var msgType = try getMsgType(allocator, msg[0..]);

            if (msgType == .Init) {
                const msgData = try parseInitMessage(allocator, msg[0..]);
                const replyMsg = handleInitMessage(msgData, &node);
                const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
                try stdout.print("{s}\n", .{reply});
            } else if (msgType == .Echo) {
                const msgData = try parseEchoMessage(allocator, msg[0..]);
                const replyMsg = handleEchoMessage(msgData, &node);
                const reply = try json.stringifyAlloc(allocator, replyMsg, .{});
                try stdout.print("{s}\n", .{reply});
            } else {
                std.debug.print("You fucked up\n", .{});
            }
        }
    }
}

const initMsg: []const u8 =
    \\ { "id": 0, "src": "c1", "dest": "n1", "body": { "type": "init", "msg_id": 1, "node_id": "n1", "node_ids": ["n1", "n2", "n3"] } }
;

const echoMsg: []const u8 =
    \\ { "id": 1, "src": "c1", "dest": "n1", "body": { "type": "echo", "msg_id": 1, "echo": "Please echo 35" } }
;

test "parses init message" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var msg: Msg(Init) = try parseInitMessage(allocator, initMsg);
    defer json.parseFree(Msg(Init), msg, .{ .allocator = allocator });

    try testing.expect(mem.eql(u8, msg.body.node_ids[0], "n1"));
}

test "handles init message" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const msg: Msg(Init) = try parseInitMessage(allocator, initMsg);
    defer json.parseFree(Msg(Init), msg, .{ .allocator = allocator });

    var node = Node{};
    const reply: Msg(InitReply) = handleInitMessage(msg, &node);

    try testing.expect(mem.eql(u8, reply.body.type, "init_ok"));
    try testing.expect(mem.eql(u8, node.id.?, "n1"));
}

test "parses echo message" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var msg = try parseEchoMessage(allocator, echoMsg);
    defer json.parseFree(Msg(Echo), msg, .{ .allocator = allocator });

    try testing.expect(mem.eql(u8, msg.body.type, "echo"));
}

test "handles echo message" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var node = Node{ .id = "n1" };
    var msg = try parseEchoMessage(allocator, echoMsg);
    defer json.parseFree(Msg(Echo), msg, .{ .allocator = allocator });

    const reply: Msg(EchoReply) = handleEchoMessage(msg, &node);

    try testing.expect(mem.eql(u8, reply.body.type, "echo_ok"));
    try testing.expect(mem.eql(u8, reply.body.echo, "Please echo 35"));
}

test "parses message into dynamic object" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(initMsg);
    defer tree.deinit();

    const body = tree.root.Object.get("body");
    const bodyType = body.?.Object.get("type");
    try testing.expect(mem.eql(u8, bodyType.?.String, "init"));
}
