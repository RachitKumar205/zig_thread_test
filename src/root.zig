//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const matrix = @import("matrix.zig");
const primes = @import("primes.zig");

const fs = std.fs;

const Proc = enum { matrix, primes };
pub const Schedule = enum { sequential, chunked, cyclic, dynamic };

const Err = error{
    InvalidConfig,
};

const MatrixCfg = struct {
    run: bool,
    schedule: []u8,
    M: usize,
    N: usize,
    P: usize,
};

const PrimesCfg = struct {
    run: bool,
    schedule: []u8,
    N: usize = 10,
};

const Schema = struct {
    n_threads: usize,
    matrix: MatrixCfg,
    prime: PrimesCfg,
};

fn parseSchedule(s: []const u8) !Schedule {
    return std.meta.stringToEnum(Schedule, s) orelse Err.InvalidConfig;
}

pub fn run() !void {
    const file = try fs.cwd().openFile("config.json", .{});
    defer file.close();

    var file_buffer: [4096]u8 = undefined;
    const bytes = try file.read(&file_buffer);
    const json_string = file_buffer[0..bytes];

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const parsed = try std.json.parseFromSlice(Schema, arena.allocator(), json_string, .{});
    defer parsed.deinit();

    const cfg = parsed.value;

    if (cfg.matrix.run == cfg.prime.run) {
        std.debug.print("Invalid config: choose exactly one process\n", .{});
        return Err.InvalidConfig;
    }

    const n_threads_cfg = cfg.n_threads;

    if (cfg.matrix.run) {
        const schedule = try parseSchedule(cfg.matrix.schedule);

        const n_threads =
            if (schedule == .sequential) 1 else n_threads_cfg;

        try matrix.run(
            schedule,
            cfg.matrix.M,
            cfg.matrix.N,
            cfg.matrix.P,
            n_threads,
        );
        return;
    } else {
        const schedule = try parseSchedule(cfg.prime.schedule);
        const n_threads =
            if (schedule == .sequential) 1 else n_threads_cfg;
        const prime_N = try std.math.powi(usize, 10, cfg.prime.N);

        try primes.run(schedule, prime_N, n_threads);
    }
}
