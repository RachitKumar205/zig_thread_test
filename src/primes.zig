const std = @import("std");

const N: usize = 100000000;
var NUM_THREADS: usize = undefined;

const Schedule = enum { sequential, chunked, cyclic, dynamic };

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

pub fn main() !void {
    NUM_THREADS = try std.Thread.getCpuCount();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    var timer = try std.time.Timer.start();

    // Sequential
    std.debug.print("\n--- Case 0: Sequential ---\n", .{});
    var sched_seq = try Scheduler.init(al, 1, N, .sequential);
    defer sched_seq.deinit(al);

    timer.reset();
    try sched_seq.compute_primes();
    const t_seq = timer.read();
    const c_seq = sched_seq.prime_count.load(.monotonic);
    std.debug.print("Primes ≤ {d}: {d}\n", .{ N, c_seq });

    // Chunked
    std.debug.print("\n--- Case 1: Chunked ---\n", .{});
    var sched_chunk = try Scheduler.init(al, NUM_THREADS, N, .chunked);
    defer sched_chunk.deinit(al);

    timer.reset();
    try sched_chunk.compute_primes();
    const t_chunk = timer.read();
    const c_chunk = sched_chunk.prime_count.load(.monotonic);
    std.debug.print("Primes ≤ {d}: {d}\n", .{ N, c_chunk });

    // Cyclic
    std.debug.print("\n--- Case 2: Cyclic ---\n", .{});
    var sched_cyc = try Scheduler.init(al, NUM_THREADS, N, .cyclic);
    defer sched_cyc.deinit(al);

    timer.reset();
    try sched_cyc.compute_primes();
    const t_cyc = timer.read();
    const c_cyc = sched_cyc.prime_count.load(.monotonic);
    std.debug.print("Primes ≤ {d}: {d}\n", .{ N, c_cyc });

    // Dynamic
    std.debug.print("\n--- Case 3: Dynamic ---\n", .{});
    var sched_dyn = try Scheduler.init(al, NUM_THREADS, N, .dynamic);
    defer sched_dyn.deinit(al);

    timer.reset();
    try sched_dyn.compute_primes();
    const t_dyn = timer.read();
    const c_dyn = sched_dyn.prime_count.load(.monotonic);
    std.debug.print("Primes ≤ {d}: {d}\n", .{ N, c_dyn });

    std.debug.print(
        "\nTiming (ns):\n  Sequential: {d}\n  Chunked:    {d}\n  Cyclic:     {d}\n  Dynamic:    {d}\n",
        .{ t_seq, t_chunk, t_cyc, t_dyn },
    );
}
