const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ColorConfig = std.io.tty.Config;
const Color = std.io.tty.Color;

const version = "1.4.0";
const default_delims = " \t\n\r|,;:";
const usage_text: []const u8 =
    \\Usage: 
    \\  pc [numbers...] or ... | pc
    \\  Calculate the percent change and times difference between a sequence of numbers.
    \\
    \\Arguments:
    \\  numbers...         : A sequence of numbers for which the differences are to be calculated.
    \\  Special Arguments:
    \\    -                : Reads input from stdin.
    \\
    \\Options:
    \\  -h, --help         : Show this help message and exit.
    \\  -v, --version      : Show version information and exit.
    \\  -d, --delimiters   : Specify extra delimiters (defaults: " \t\n\r|,;").
    \\                       Example: echo "1,2,3" | pc -d ","
    \\  -f, --fixed [N]    : Changes are relative to Nth number (default: 1).
    \\                       Examples:
    \\                         echo "1,2,3" | pc -f 2  (second element)
    \\                         echo "1,2,3" | pc -f -1 (last element)
    \\  -r, --reverse      : Reverse the order of the numbers.
    \\      --raw          : Show numbers in raw form (e.g. 1000000 instead of 1MiB).
    \\      --[no-]color   : Enable/disable color output (default: auto).
    \\      --format <f>   : Specify output format (options: json, csv).
    \\  -w, --warnings     : Show warnings for invalid numbers (default: false).
    \\
    \\Symbols:
    \\  ↑                 : Positive percent change.
    \\  ↓                 : Negative percent change.
    \\  →                 : No change.
    \\
    \\Notes:
    \\  - At least 2 numbers required for calculation.
    \\  - Invalid numbers in sequence will be skipped.
    \\
    \\Examples:
    \\  pc 10 20 30
    \\  echo "10,20,30" | pc -d ","
    \\  echo "128 221 150" | pc -f
    \\  echo "128 221 150" | pc -r
    \\
;

fn parseNum(s: []const u8, print_warning: bool) ?f32 {
    const val = std.fmt.parseFloat(f32, s) catch {
        if (print_warning) std.debug.print("skipping invalid number: '{s}'\n", .{s});
        return null;
    };
    return val;
}

fn percentDiff(a: f32, b: f32) f32 {
    if (a == 0) {
        return if (b == 0) 0.0 else std.math.inf(f32);
    }
    return (b - a) / @abs(a) * 100.0;
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
    if (@abs(num - std.math.round(num)) < 0.001) {
        return 0;
    } else {
        return 2;
    }
}

/// Returns the precision to use for formatting a number based on how far it is
/// from 0. Numbers that are closer to 0 will have more decimal places. Whole
/// numbers will have no decimal places.
fn sizeFormatPrecision(num: f32) u8 {
    var diff: u64 = 0;
    if (std.math.isInf(num)) {
        diff = std.math.maxInt(u64);
    } else {
        // no decimal places if its whole
        if (@floor(num) == num) {
            return 0;
        }
        const rounded = @round(@abs(num));
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

    fn color(s: Sign) Color {
        return switch (s) {
            .Positive => Color.green,
            .Negative => Color.red,
            .Neutral => Color.white,
        };
    }
};

const ColorChoice = enum {
    Auto,
    Always,
    Never,

    fn colorConfig(self: ColorChoice, file: std.fs.File) ColorConfig {
        return switch (self) {
            .Auto => {
                if (file.isTty() and file.supportsAnsiEscapeCodes()) {
                    return .escape_codes;
                } else {
                    return .no_color;
                }
            },
            .Always => .escape_codes,
            .Never => .no_color,
        };
    }
};

const Format = enum {
    Default,
    Csv,
    Json,

    fn fromStr(s: []const u8) ?Format {
        if (std.mem.eql(u8, s, "default")) {
            return .Default;
        } else if (std.mem.eql(u8, s, "csv")) {
            return .Csv;
        } else if (std.mem.eql(u8, s, "json")) {
            return .Json;
        } else {
            return null;
        }
    }

    fn all() []const u8 {
        return "csv, json";
    }
};

const Row = struct {
    const Self = @This();

    percent: f32,
    times: f32,
    prev: f32,
    cur: f32,

    fn init(prev: f32, cur: f32) Self {
        return .{
            .percent = percentDiff(prev, cur),
            .times = timesDiff(prev, cur),
            .prev = prev,
            .cur = cur,
        };
    }
};

/// A single item in the diff table. Holds strings that are pre-formatted so we
/// can calculate the padding for each column.
const StringRow = struct {
    const Self = @This();

    sign: Sign,
    percent: []const u8,
    times: []const u8,
    prev: []const u8,
    cur: []const u8,

    fn init(allocator: Allocator, row: Row, raw: bool) !Self {
        const prev = row.prev;
        const cur = row.cur;
        const percent_diff = row.percent;
        const times_diff = row.times;

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

    fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.percent);
        allocator.free(self.times);
        allocator.free(self.prev);
        allocator.free(self.cur);
    }

    fn print(self: *Self, writer: anytype, maxes: Maxes, colorizer: ColorConfig) !void {
        try colorizer.setColor(writer, self.sign.color());
        try writer.print("{[sign]s}", .{
            .sign = self.sign.arrow(),
        });
        try writer.print(" {[perc]s: >[perc_padding]}% {[times]s: >[times_padding]}x ", .{
            .perc = self.percent,
            .perc_padding = maxes.percent + 1,
            .times = self.times,
            .times_padding = maxes.times + 1,
        });
        try colorizer.setColor(writer, Color.reset);
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

const ComparisonTarget = union(enum) {
    Moving,
    Fixed: i64, // 1 based, 0 and 1 are the same
};

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

    const ouput_handle = std.io.getStdOut();
    var stdout_buf = std.io.bufferedWriter(ouput_handle.writer());
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
    var target: ComparisonTarget = .Moving;
    var raw = false;
    var reverse = false;
    var color: ColorChoice = .Auto;
    var format: Format = .Default;
    var print_warnings: bool = false;

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
            target = ComparisonTarget{ .Fixed = 0 }; // default to 0
            if (arg_i + 1 < args.len) {
                // Try to parse, if we succeed thats the value, otherwise its a
                // flag. If the number is too large, it will be ignored and then
                // parsed as a number to be compared against.
                const next_arg = args[arg_i + 1];
                if (std.fmt.parseInt(i64, next_arg, 10) catch null) |fixed_val| {
                    target = ComparisonTarget{ .Fixed = fixed_val };
                    arg_i += 1;
                    continue;
                }
            }
        } else if (std.mem.eql(u8, arg, "--raw")) {
            raw = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--reverse")) {
            reverse = true;
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
        } else if (std.mem.eql(u8, arg, "--format")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("pc: missing argument for {s}\n", .{arg});
                try stdout.writeAll(usage_text);
                return std.process.exit(1);
            }
            const format_str = args[arg_i];
            if (Format.fromStr(format_str)) |f| {
                format = f;
            } else {
                std.debug.print("pc: invalid format: {s}. valid formats are: {s}\n", .{ format_str, Format.all() });
                try stdout.writeAll(usage_text);
                return std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--color")) {
            color = .Always;
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            color = .Never;
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--warnings")) {
            print_warnings = true;
        } else if (std.mem.eql(u8, arg, "-")) {
            break;
        } else if (parseNum(arg, print_warnings)) |num| {
            try nums.append(num);
        }
    }

    // if no nums, read from stdin
    if (nums.items.len == 0) {
        const input = std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch |e| {
            std.debug.print("pc: error reading stdin: {s}\n", .{@errorName(e)});
            return std.process.exit(1);
        };
        var it = std.mem.tokenizeAny(u8, input, delims.items);
        while (it.next()) |s| {
            if (parseNum(s, print_warnings)) |num| {
                try nums.append(num);
            }
        }
    }

    if (nums.items.len < 2) {
        std.debug.print("pc: need at least 2 numbers\n", .{});
        try stdout.writeAll(usage_text);
        return std.process.exit(1);
    }

    if (reverse) {
        std.mem.reverse(f32, nums.items);
    }

    // construct the base type, collecting all the rows
    var rows: ArrayList(Row) = ArrayList(Row).init(allocator);
    defer rows.deinit();

    // calculate the current index based on the target
    const cur_idx = switch (target) {
        .Moving => 0, // start at the first number
        .Fixed => |index| blk: {
            // account for negative indices and clamp
            const nums_len: i64 = @intCast(nums.items.len);
            const adjusted_index = if (index < 0) nums_len + index else index - 1; // 1 based
            const final_idx: usize = @intCast(std.math.clamp(adjusted_index, 0, nums_len - 1));
            break :blk final_idx;
        },
    };

    var cur = nums.items[cur_idx];
    for (nums.items, 0..) |num, i| {
        if (i == cur_idx) continue;
        const row = Row.init(cur, num);
        try rows.append(row);
        if (target == .Moving) cur = num;
    }

    switch (format) {
        .Default => {
            var string_rows: ArrayList(StringRow) = ArrayList(StringRow).init(allocator);
            defer string_rows.deinit();
            var maxes: Maxes = .{};
            for (rows.items) |row| {
                const srow = try StringRow.init(allocator, row, raw);
                try string_rows.append(srow);
                if (srow.percent.len > maxes.percent) maxes.percent = srow.percent.len;
                if (srow.times.len > maxes.times) maxes.times = srow.times.len;
                if (srow.prev.len > maxes.prev) maxes.prev = srow.prev.len;
                if (srow.cur.len > maxes.cur) maxes.cur = srow.cur.len;
            }

            const color_config = color.colorConfig(ouput_handle);
            for (string_rows.items) |*row| {
                try row.print(stdout, maxes, color_config);
                row.deinit(allocator);
            }
        },
        .Csv => {
            try stdout.print("percent,times,prev,cur\n", .{});
            for (rows.items) |row| {
                try stdout.print("{d},{d},{d},{d}\n", .{ row.percent, row.times, row.prev, row.cur });
            }
        },
        .Json => {
            try std.json.stringify(rows.items, .{}, stdout);
            try stdout.print("\n", .{});
        },
    }
}
