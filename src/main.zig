const std = @import("std");
const print = @import("std").debug.print;
const Io = std.Io;

const base64_encoder = @import("base64_encoder");

const Base64Error = error{InvalidChar};

const Base64 = struct {
    _table: *const [64]u8,

    pub fn init() Base64 {
        return Base64{ ._table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" };
    }

    pub fn char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    pub fn index_from_char(self: Base64, char: u8) Base64Error!u8 {
        if (char == '=') {
            return 64;
        }

        var output_index: u8 = 0;

        for (self._table) |v| {
            if (char == v) {
                return output_index;
            }
            output_index += 1;
        }
        return Base64Error.InvalidChar;
    }
};
const _base64 = Base64.init();

const Encoder = struct {
    pub fn init() Encoder {
        return Encoder{};
    }

    pub fn encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) {
            return "";
        }

        var list = try std.ArrayList(u8).initCapacity(allocator, ((input.len + 2) / 3) * 4);

        var i: usize = 0;
        var window: []const u8 = undefined;
        var tmp: [3]u8 = .{ 0, 0, 0 };

        var b0: u8 = undefined;
        var b1: u8 = undefined;
        var b2: u8 = undefined;

        var e0: u6 = undefined;
        var e1: u6 = undefined;
        var e2: u6 = undefined;
        var e3: u6 = undefined;

        while (i < input.len) : (i += 3) {
            var count: usize = 0;
            if (i + 3 > input.len) {
                var z: usize = 0;
                while (i + z < input.len) : (z += 1) {
                    tmp[z] = input[i + z];
                    count += 1;
                }
                window = &tmp;
            } else {
                window = input[i..(i + 3)];
            }

            if (count == 0) {
                // the case when window is full
                b0 = window[0];
                b1 = window[1];
                b2 = window[2];

                e0 = @intCast(b0 >> 2);
                e1 = @intCast(((b0 & 0x03) << 4 | (b1 >> 4)));
                e2 = @intCast(((b1 & 0x0f) << 2) | (b2 >> 6));
                e3 = @intCast(b2 & 0x3f);

                list.appendAssumeCapacity(_base64.char_at(e0));
                list.appendAssumeCapacity(_base64.char_at(e1));
                list.appendAssumeCapacity(_base64.char_at(e2));
                list.appendAssumeCapacity(_base64.char_at(e3));
            } else if (count == 1) {
                // when the window has 1 item in it
                b0 = window[0];

                e0 = @intCast(b0 >> 2);
                e1 = @intCast((b0 & 0x03) << 4);

                list.appendAssumeCapacity(_base64.char_at(e0));
                list.appendAssumeCapacity(_base64.char_at(e1));
                list.appendAssumeCapacity('=');
                list.appendAssumeCapacity('=');
            } else if (count == 2) {
                // when the window was 2 items in it
                b0 = window[0];
                b1 = window[1];

                e0 = @intCast(b0 >> 2);
                e1 = @intCast(((b0 & 0x03) << 4) | (b1 >> 4));
                e2 = @intCast((b1 & 0x0f) << 2);

                list.appendAssumeCapacity(_base64.char_at(e0));
                list.appendAssumeCapacity(_base64.char_at(e1));
                list.appendAssumeCapacity(_base64.char_at(e2));
                list.appendAssumeCapacity('=');
            }
        }

        return try list.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) {
            return "";
        }

        var list = try std.ArrayList(u8).initCapacity(allocator, ((input.len + 3) / 4) * 3);

        var count: usize = 0;
        var tmp: [4]u8 = .{ 0, 0, 0, 0 };

        var e0: u8 = undefined;
        var e1: u8 = undefined;
        var e2: u8 = undefined;

        for (0..input.len) |i| {
            tmp[count] = try _base64.index_from_char(input[i]);
            count += 1;

            // end of sequence
            if (count == 4) {
                e0 = (tmp[0] << 2) | (tmp[1] >> 4);
                list.appendAssumeCapacity(e0);

                if (tmp[2] != 64) {
                    e1 = (tmp[1] << 4) | (tmp[2] >> 2);
                    list.appendAssumeCapacity(e1);
                }

                if (tmp[3] != 64) {
                    e2 = (tmp[2] << 6) | tmp[3];
                    list.appendAssumeCapacity(e2);
                }

                count = 0;
            }
        }

        return try list.toOwnedSlice(allocator);
    }
};

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const base64_message = try Encoder.encode(allocator, &[_]u8{'H'});
    defer allocator.free(base64_message);
    try stdout_writer.print("encoded message: {s}\n", .{base64_message});

    const decoded = try Encoder.decode(allocator, &[_]u8{ 'S', 'A', '=', '=' });
    defer allocator.free(decoded);
    try stdout_writer.print("decoded message: {s}\n", .{decoded});

    try stdout_writer.flush(); // Don't forget to flush!
}
