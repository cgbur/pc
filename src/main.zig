const std = @import("std");
const Allocator = std.mem.Allocator;
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

const version = "0.1.0";
const default_delims = " \t\n\r|";
const usage_text: []const u8 =
    \\Usage: pc [numbers...] or ... | pc
    \\Calculate the percent change between numbers.
    \\
    \\Arguments:
    \\  numbers...       : A sequence of numbers for which the percent change is to be calculated.
    \\
    \\Special Arguments:
    \\  -                 : Reads input from stdin.
    \\
    \\Options:
    \\  -h, --help        : Show this help message and exit.
    \\  -v, --version     : Show version information and exit.
    \\  -d, --delimiters  : Specify extra delimiter(s) to use for parsing (defaults: " \t\n\r|").
    \\                      Example: echo "1,2,3" | pc -d ","
    \\  -f, --fixed       : All percent changes are calculated relative to the first number.
    \\  -r, --raw         : Show numbers in raw form (e.g. 1000000 instead of 1MiB).
    \\
    \\Symbols:
    \\  ↑                 : Indicates a positive percent change.
    \\  ↓                 : Indicates a negative percent change.
    \\  →                 : Indicates no change.
    \\
    \\Notes:
    \\  - At least 2 numbers are required for calculation.
    \\  - Invalid numbers in the sequence will be skipped.
    \\
    \\Example:
    \\  pc 10 20 30
    \\  echo "10,20,30" | pc -d ","
    \\  echo "128 221 150" | pc -f
    \\  echo "128 221 150" | pc -r
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

fn numberPrecision(num: f32) u8 {
    // if its a whole number, don't show decimal places otherwise, show up to 2
    // decimal places
    if (@fabs(num - std.math.round(num)) < 0.001) {
        return 0;
    } else {
        return 2;
    }
}

fn sizeFormatPrecision(num: f32) u8 {
    const diff: u64 = @intFromFloat(std.math.round(@fabs(num)));
    switch (diff) {
        0...10 => return 2,
        11...200 => return 1,
        else => return 0,
    }
}

fn fancyPrint(writer: anytype, prev: f32, cur: f32, raw: bool) !void {
    const diff = percentDiff(prev, cur);
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
    const times: f32 = (cur / prev);

    // write the sign and percent change
    try writer.print("{[sign]s} {[perc]d: >6.[diff_prec]}%", .{
        .diff_prec = numberPrecision(diff),
        .sign = symbol,
        .perc = diff,
    });

    // write the times change
    try writer.print(" {[times]d: >6.[times_prec]}x {[reset]s} ", .{
        .times = times,
        .times_prec = numberPrecision(times),
        .reset = EscapeCodes.reset,
    });

    // write the previous and current values
    if (raw or (prev < 1000.0 and cur < 1000.0)) {
        const padding = 6;
        try writer.print("[{[prev]d: >[padding].[prev_prec]} → {[cur]d: <[padding].[cur_prec]}]", .{
            .prev_prec = numberPrecision(prev),
            .cur_prec = numberPrecision(cur),
            .prev = prev,
            .cur = cur,
            .padding = padding,
        });
    } else {
        const padding = 8;
        const prev_int: u64 = @intFromFloat(prev);
        const cur_int: u64 = @intFromFloat(cur);
        try writer.print("[{[prev]s: >[padding].[prev_prec]} → {[cur]s: <[padding].[cur_prec]}]", .{
            .prev_prec = sizeFormatPrecision(diff),
            .cur_prec = sizeFormatPrecision(diff),
            .prev = std.fmt.fmtIntSizeBin(prev_int),
            .cur = std.fmt.fmtIntSizeBin(cur_int),
            .padding = padding,
        });
    }

    try writer.print("\n", .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout_buf.flush() catch {};
    var stdout = stdout_buf.writer();

    const args = try std.process.argsAlloc(allocator);
    var nums = ArrayList(f32).init(allocator);
    defer nums.deinit();

    var delims = try ArrayList(u8).initCapacity(allocator, default_delims.len);
    defer delims.deinit();
    inline for (" \t\n\r") |c| {
        try delims.append(c);
    }
    var fixed = false;
    var raw = false;

    // parse args
    var arg_i: usize = 1;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage_text);
            try stdout_buf.flush();
            return std.process.cleanExit();
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            try stdout.print("pc {s}\n", .{version});
            try stdout_buf.flush();
            return std.process.cleanExit();
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--fixed")) {
            fixed = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--raw")) {
            raw = true;
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
        try fancyPrint(stdout, cur, num, raw);
        if (!fixed) cur = num;
    }
}
