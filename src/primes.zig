const std = @import("std");
const root = @import("root.zig");

var N: usize = 100000000;
var NUM_THREADS: usize = undefined;

const Schedule = root.Schedule;

const Scheduler = struct {
    threads: []std.Thread,
    number: usize,
    prime_count: std.atomic.Value(usize),
    mode: Schedule,

    pub fn init(
        al: std.mem.Allocator,
        num_threads: usize,
        number: usize,
        mode: Schedule,
    ) !Scheduler {
        const threads_buf = try al.alloc(std.Thread, num_threads);
        return Scheduler{
            .threads = threads_buf,
            .number = number,
            .prime_count = std.atomic.Value(usize).init(0),
            .mode = mode,
        };
    }

    pub fn deinit(self: *Scheduler, al: std.mem.Allocator) void {
        al.free(self.threads);
        self.* = undefined;
    }

    pub fn compute_primes(self: *Scheduler) !void {
        switch (self.mode) {
            .sequential => self.compute_primes_sequential(),
            .chunked => try self.compute_primes_chunked(),
            .cyclic => try self.compute_primes_cyclic(),
            .dynamic => try self.compute_primes_dynamic(),
        }
    }

    pub fn compute_primes_sequential(self: *Scheduler) void {
        for (2..self.number + 1) |num| {
            is_prime(num, &(self.prime_count));
        }
    }

    pub fn compute_primes_chunked(self: *Scheduler) !void {
        const max_threads = @min(NUM_THREADS, self.number);
        const chunk_size = (self.number - 1) / max_threads;

        for (0..max_threads) |id| {
            const start_num = id * chunk_size + 2;
            const end_num = if (id == max_threads - 1)
                self.number + 1
            else
                start_num + chunk_size;

            const thread = try std.Thread.spawn(.{}, prime_worker_chunked, .{
                start_num,
                end_num,
                &(self.prime_count),
            });

            self.threads[id] = thread;
        }

        for (self.threads[0..max_threads]) |thread| {
            thread.join();
        }
    }

    pub fn compute_primes_cyclic(self: *Scheduler) !void {
        const max_threads = @min(NUM_THREADS, self.number);
        for (0..max_threads) |id| {
            const thread = try std.Thread.spawn(.{}, prime_worker_cyclic, .{
                max_threads,
                id,
                self.number,
                &(self.prime_count),
            });

            self.threads[id] = thread;
        }

        for (self.threads[0..max_threads]) |thread| {
            thread.join();
        }
    }

    pub fn compute_primes_dynamic(self: *Scheduler) !void {
        const max_threads = @min(NUM_THREADS, self.number);
        var next_num = std.atomic.Value(usize).init(2);

        for (0..max_threads) |id| {
            const thread = try std.Thread.spawn(.{}, prime_worker_dynamic, .{
                self.number,
                &next_num,
                &(self.prime_count),
            });

            self.threads[id] = thread;
        }

        for (self.threads[0..max_threads]) |thread| {
            thread.join();
        }
    }
};

pub fn prime_worker_chunked(
    start_num: usize,
    end_num: usize,
    prime_count_ref: *std.atomic.Value(usize),
) void {
    for (start_num..end_num) |num| {
        is_prime(num, prime_count_ref);
    }
}

pub fn prime_worker_cyclic(
    interval: usize,
    thread_id: usize,
    max_number: usize,
    prime_count_ref: *std.atomic.Value(usize),
) void {
    var num = thread_id + 2;
    while (num < max_number + 1) : (num += interval) {
        is_prime(num, prime_count_ref);
    }
}

pub fn prime_worker_dynamic(
    max_number: usize,
    next_num: *std.atomic.Value(usize),
    prime_count_ref: *std.atomic.Value(usize),
) void {
    while (true) {
        const num = next_num.fetchAdd(1, .monotonic);
        if (num >= max_number + 1) break;
        is_prime(num, prime_count_ref);
    }
}

pub fn is_prime(
    num: usize,
    prime_count_ref: *std.atomic.Value(usize),
) void {
    if (num < 2) {
        return;
    }

    if (num == 2) {
        _ = prime_count_ref.fetchAdd(1, .monotonic);
        return;
    }

    if (num % 2 == 0) return;

    var fac: usize = 3;
    while (fac * fac <= num) : (fac += 2) {
        if (num % fac == 0) return;
    }

    _ = prime_count_ref.fetchAdd(1, .monotonic);
}

pub fn run(schedule: Schedule, n: usize, num_threads: usize) !void {
    NUM_THREADS = num_threads;
    N = n;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    var timer = try std.time.Timer.start();

    std.debug.print("\n--------EVALUATING---------\n", .{});
    var seq = try Scheduler.init(al, NUM_THREADS, N, schedule);
    defer seq.deinit(al);

    timer.reset();
    try seq.compute_primes();
    const time = timer.read();
    const count = seq.prime_count.load(.monotonic);
    std.debug.print("Primes ≤ {d}: {d}\n", .{ N, count });

    std.debug.print(
        "\nTiming (ns): {d}",
        .{time},
    );
}
