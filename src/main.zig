const std = @import("std");
const builtin = @import("builtin");
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

const version = "0.2.3";
const default_delims = " \t\n\r|,;:";
const usage_text: []const u8 =
    \\Usage: pc [numbers...] or ... | pc
    \\Calculate the percent change between numbers.
    \\
    \\Arguments:
    \\  numbers...        : A sequence of numbers for which the differences are to be calculated.
    \\
    \\Special Arguments:
    \\  -                 : Reads input from stdin.
    \\
    \\Options:
    \\  -h, --help        : Show this help message and exit.
    \\  -v, --version     : Show version information and exit.
    \\  -d, --delimiters  : Specify extra delimiter(s) to use for parsing (defaults: " \t\n\r|,;:").
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
    if (a == 0) {
        return if (b == 0) 0.0 else std.math.inf(f32);
    }

    return (b - a) / @fabs(a) * 100.0;
}

test "calculates percent differences correctly" {
    try std.testing.expect(percentDiff(10.0, 20.0) == 100.0);
    try std.testing.expect((percentDiff(5.4, 6.7) - 24.07) < 0.01);
    try std.testing.expect(percentDiff(1.0, 1.0) == 0.0);
    try std.testing.expect(percentDiff(0.0, 0.0) == 0.0);
    try std.testing.expect((percentDiff(14.3, 12.2) + 14.685) < 0.01);
    try std.testing.expect((percentDiff(-10.0, -5.0) - 50.0) < 0.1);
    try std.testing.expect((percentDiff(-10.0, -20.0) + 100.0) < 0.1);
}

fn timesDiff(a: f32, b: f32) f32 {
    if (a == 0) {
        return if (b == 0) 0.0 else std.math.inf(f32);
    }

    return b / a;
}

test "calculates times differences correctly" {
    try std.testing.expect(timesDiff(10.0, 20.0) == 2.0);
    try std.testing.expect((timesDiff(5.4, 6.7) - 1.24) < 0.01);
    try std.testing.expect(timesDiff(1.0, 1.0) == 1.0);
    try std.testing.expect(timesDiff(0.0, 0.0) == 0.0);
    try std.testing.expect(timesDiff(-10.0, -5.0) == 0.5);
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
    var diff: u64 = 0;
    if (std.math.isInf(num)) {
        diff = std.math.maxInt(u64);
    } else {
        const rounded = @round(@fabs(num));
        if (rounded > std.math.maxInt(u64)) {
            diff = std.math.maxInt(u64);
        } else {
            diff = @intFromFloat(rounded);
        }
    }

    switch (diff) {
        0...10 => return 2,
        11...200 => return 1,
        else => return 0,
    }
}

const Sign = enum {
    Positive,
    Negative,
    Neutral,

    fn fromNum(num: f32) Sign {
        if (num > 0) {
            return .Positive;
        } else if (num < 0) {
            return .Negative;
        } else {
            return .Neutral;
        }
    }

    fn arrow(s: Sign) []const u8 {
        return switch (s) {
            .Positive => "↑",
            .Negative => "↓",
            .Neutral => "→",
        };
    }

    fn color(s: Sign) []const u8 {
        return switch (s) {
            .Positive => EscapeCodes.green,
            .Negative => EscapeCodes.red,
            .Neutral => EscapeCodes.white,
        };
    }
};

/// A single item in the diff table. Holds strings that are pre-formatted so we
/// can calculate the padding for each column.
const DiffItem = struct {
    sign: Sign,
    percent: []const u8,
    times: []const u8,
    prev: []const u8,
    cur: []const u8,

    fn deinit(self: *DiffItem, allocator: Allocator) void {
        allocator.free(self.percent);
        allocator.free(self.times);
        allocator.free(self.prev);
        allocator.free(self.cur);
    }

    fn print(self: *DiffItem, writer: anytype, maxes: anytype) !void {
        try writer.print("{[color]s}{[sign]s}", .{
            .sign = Sign.arrow(self.sign),
            .color = self.sign.color(),
        });

        try writer.print(" {[perc]s: >[perc_padding]}% {[times]s: >[times_padding]}x {[reset]s}", .{
            .perc = self.percent,
            .perc_padding = maxes.percent + 1,
            .times = self.times,
            .times_padding = maxes.times + 1,
            .reset = EscapeCodes.reset,
        });

        try writer.print(" [ {[prev]s: >[prev_padding]} → {[cur]s: <[cur_padding]} ]", .{
            .prev = self.prev,
            .cur = self.cur,
            .prev_padding = maxes.prev,
            .cur_padding = maxes.cur,
        });

        try writer.print("\n", .{});
    }
};

const Maxes = struct {
    percent: usize = 0,
    times: usize = 0,
    prev: usize = 0,
    cur: usize = 0,
};

fn makeRow(allocator: Allocator, prev: f32, cur: f32, raw: bool) !DiffItem {
    const percent_diff = percentDiff(prev, cur);
    const times_diff = timesDiff(prev, cur);
    const sign = Sign.fromNum(percent_diff);

    const percent = try std.fmt.allocPrint(allocator, "{[perc]d:.[diff_prec]}", .{
        .perc = percent_diff,
        .diff_prec = sizeFormatPrecision(percent_diff),
    });

    const times = try std.fmt.allocPrint(allocator, "{[times]d:.[times_prec]}", .{
        .times = times_diff,
        .times_prec = sizeFormatPrecision(times_diff),
    });

    var previous: []const u8 = undefined;
    var current: []const u8 = undefined;
    const nums_are_small = (prev < 1000.0 and cur < 1000.0);
    const any_are_negative = (prev < 0.0 or cur < 0.0);
    const wont_fit_in_u64 = (prev > std.math.maxInt(u64) or cur > std.math.maxInt(u64));
    if (raw or nums_are_small or any_are_negative or wont_fit_in_u64) {
        previous = try std.fmt.allocPrint(allocator, "{[prev]d:.[prev_prec]}", .{
            .prev = prev,
            .prev_prec = numberPrecision(prev),
        });
        current = try std.fmt.allocPrint(allocator, "{[cur]d:.[cur_prec]}", .{
            .cur = cur,
            .cur_prec = numberPrecision(cur),
        });
    } else {
        const prev_int: u64 = @intFromFloat(prev);
        const cur_int: u64 = @intFromFloat(cur);
        const precision = sizeFormatPrecision(percent_diff);
        previous = try std.fmt.allocPrint(allocator, "{[prev]s:.[prec]}", .{
            .prev = std.fmt.fmtIntSizeBin(prev_int),
            .prec = precision,
        });
        current = try std.fmt.allocPrint(allocator, "{[cur]s:.[prec]}", .{
            .cur = std.fmt.fmtIntSizeBin(cur_int),
            .prec = precision,
        });
    }

    return .{
        .sign = sign,
        .percent = percent,
        .times = times,
        .prev = previous,
        .cur = current,
    };
}

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        // On Windows, the console's character encoding might not be UTF-8. Set the
        // console code page to UTF-8 (code 65001) to ensure that special
        // characters are displayed correctly.
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
    }
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
    inline for (default_delims) |delim| {
        try delims.append(delim);
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

    var rows: ArrayList(DiffItem) = ArrayList(DiffItem).init(allocator);
    defer rows.deinit();
    var maxes: Maxes = .{};
    var cur = nums.items[0];
    for (nums.items[1..]) |num| {
        const row = try makeRow(allocator, cur, num, raw);
        if (row.percent.len > maxes.percent) maxes.percent = row.percent.len;
        if (row.times.len > maxes.times) maxes.times = row.times.len;
        if (row.prev.len > maxes.prev) maxes.prev = row.prev.len;
        if (row.cur.len > maxes.cur) maxes.cur = row.cur.len;
        try rows.append(row);
        if (!fixed) cur = num;
    }

    for (rows.items) |*row| {
        try row.print(stdout, maxes);
        row.deinit(allocator);
    }
}
