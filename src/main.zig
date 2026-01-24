const std = @import("std");

// todo:
// clean up printing
// enum for case
// actually write other two cases
// more robust scheduler
// build system explore
// prime numbers
// yay

const M = 400;
const N = 400;
const P = 400;

var NUM_THREADS: usize = undefined;

const Matrix = struct {
    rows: usize,
    cols: usize,
    mat: []i32,

    pub fn init(al: std.mem.Allocator, rows: usize, cols: usize) !Matrix {
        const buf = try al.alloc(i32, rows * cols);
        return Matrix{ .rows = rows, .cols = cols, .mat = buf };
    }

    pub fn deinit(self: *Matrix, al: std.mem.Allocator) void {
        al.free(self.mat);
        self.* = undefined;
    }

    pub fn at(self: *const Matrix, i: usize, j: usize) *i32 {
        return &self.mat[i * self.cols + j];
    }

    pub fn fill_random(self: *Matrix, rng: anytype) void {
        for (self.mat) |*elem| {
            elem.* = rng.intRangeAtMost(i32, -10, 10);
        }
    }

    pub fn print(self: *const Matrix) void {
        for (0..self.rows) |i| {
            for (0..self.cols) |j| {
                std.debug.print("{d:4} ", .{self.at(i, j).*});
            }
            std.debug.print("\n", .{});
        }
    }
};

const Scheduler = struct {
    status: []bool,
    threads: []std.Thread,
    mat_A: *const Matrix,
    mat_B: *const Matrix,
    mat_C: Matrix,

    pub fn init(al: std.mem.Allocator, mat_A: *const Matrix, mat_B: *const Matrix, num_threads: usize) !Scheduler {
        const status_buf = try al.alloc(bool, mat_A.rows);
        const threads_buf = try al.alloc(std.Thread, num_threads);

        @memset(status_buf, false);

        return Scheduler{
            .status = status_buf,
            .threads = threads_buf,
            .mat_A = mat_A,
            .mat_B = mat_B,
            .mat_C = try Matrix.init(al, mat_A.rows, mat_B.cols),
        };
    }

    pub fn deinit(self: *Scheduler, al: std.mem.Allocator) void {
        al.free(self.status);
        al.free(self.threads);
        self.mat_C.deinit(al);
        self.* = undefined;
    }

    pub fn compute_matrix(self: *Scheduler) !void {
        const max_threads = @min(NUM_THREADS, self.mat_C.rows);
        const chunk_size = self.mat_C.rows / max_threads;

        for (0..max_threads) |i| {
            const start_row = i * chunk_size;
            const end_row = if (i == max_threads - 1)
                self.mat_C.rows
            else
                start_row + chunk_size;

            const thread = try std.Thread.spawn(.{}, compute_rows, .{
                self.mat_A,
                self.mat_B,
                &(self.mat_C),
                start_row,
                end_row,
                self.status,
            });

            self.threads[i] = thread;
        }

        for (self.threads[0..max_threads]) |thread| {
            thread.join();
        }
    }
};

pub fn compute_rows(
    mat_A: *const Matrix,
    mat_B: *const Matrix,
    mat_C: *Matrix,
    start_row: usize,
    end_row: usize,
    row_status: []bool,
) void {
    for (start_row..end_row) |row| {
        for (0..mat_B.cols) |j| {
            var sum: i32 = 0;
            for (0..mat_A.cols) |k| {
                sum += mat_A.at(row, k).* * mat_B.at(k, j).*;
            }
            mat_C.at(row, j).* = sum;
        }

        row_status[row] = true;
    }
}

pub fn main() !void {
    NUM_THREADS = try std.Thread.getCpuCount();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    const rng = std.crypto.random;

    var mat_A = try Matrix.init(al, M, N);
    defer mat_A.deinit(al);
    mat_A.fill_random(rng);

    var mat_B = try Matrix.init(al, N, P);
    defer mat_B.deinit(al);
    mat_B.fill_random(rng);

    Matrix.print(&mat_A);
    Matrix.print(&mat_B);

    var scheduler = try Scheduler.init(al, &mat_A, &mat_B, NUM_THREADS);
    defer Scheduler.deinit(&scheduler, al);

    const a = mat_A.at(2, 3);
    std.debug.print("{}", .{a.*});

    try scheduler.compute_matrix();
    scheduler.mat_C.print();
}
