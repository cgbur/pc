const std = @import("std");
const ArrayList = std.ArrayList;

pub const EscapeCodes = struct {
    pub const dim = "\x1b[2m";
    pub const pink = "\x1b[38;5;205m";
    pub const white = "\x1b[37m";
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const green = "\x1b[32m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const reset = "\x1b[0m";
    pub const erase_line = "\x1b[2K\r";
};

const usage_text: []const u8 =
    \\ pc: percent change
    \\Usage:   pc [numbers...] or ... | pc
    \\ - is a special argument that reads from stdin 
    \\Options:
    \\ -h, --help: Show this help message
    \\ -d, --delimiters: specify extra delimter(s) to use for parsing
    \\           (default: " \t\n\r")
    \\           (example: echo "1,2,3" | pc -d ",")
    \\
;

fn parseNum(s: []const u8) ?f32 {
    const val = std.fmt.parseFloat(f32, s) catch {
        std.debug.print("skipping invalid number: '{s}'\n", .{s});
        return null;
    };
    return val;
}

fn percentDiff(a: f32, b: f32) f32 {
    return (b - a) / a * 100.0;
}

fn fancyPrint(writer: anytype, diff: f32) !void {
    const symbol = blk: {
        if (diff > 0.0) {
            try writer.print("{s}", .{EscapeCodes.green});
            break :blk "↑";
        } else if (diff < 0.0) {
            try writer.print("{s}", .{EscapeCodes.red});
            break :blk "↓";
        } else {
            try writer.print("{s}", .{EscapeCodes.white});
            break :blk "→";
        }
    };
    try writer.print("{s} {d: >6.2}%\n", .{ symbol, diff });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    var nums = ArrayList(f32).init(allocator);
    defer nums.deinit();

    const default_delims = " \t\n\r";
    var delims = try ArrayList(u8).initCapacity(allocator, default_delims.len);
    defer delims.deinit();
    inline for (" \t\n\r") |c| {
        try delims.append(c);
    }

    // parse args
    var arg_i: usize = 1;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage_text);
            return std.process.cleanExit();
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--delimiters")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("pc: missing argument for {s}\n", .{arg});
                try stdout.writeAll(usage_text);
                return std.process.exit(1);
            }
            const delim = args[arg_i];
            for (delim) |c| {
                try delims.append(c);
            }
        } else if (std.mem.eql(u8, arg, "-")) {
            break;
        } else if (parseNum(arg)) |num| {
            try nums.append(num);
        }
    }

    // if no nums, read from stdin
    if (nums.items.len == 0) {
        var input = std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch |e| {
            std.debug.print("pc: error reading stdin: {s}\n", .{@errorName(e)});
            return std.process.exit(1);
        };
        var it = std.mem.tokenizeAny(u8, input, delims.items);
        while (it.next()) |s| {
            if (parseNum(s)) |num| {
                try nums.append(num);
            }
        }
    }

    if (nums.items.len < 2) {
        std.debug.print("pc: need at least 2 numbers\n", .{});
        try stdout.writeAll(usage_text);
        return std.process.exit(1);
    }

    // calculate percent difference between each pair
    var cur = nums.items[0];
    for (nums.items[1..]) |num| {
        const diff = percentDiff(cur, num);
        try fancyPrint(stdout, diff);
        cur = num;
    }
}
