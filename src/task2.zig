const std = @import("std");
const context = @import("context.zig");

// =============================================================================
// Task 2: Fiber Class and Scheduler Implementation
// =============================================================================

// Global scheduler instance
var global_scheduler: Scheduler = undefined;

// Pointer to current fiber being executed
var current_fiber_ptr: ?*Fiber = null;

// Fiber class
pub const Fiber = struct {
    fn_ptr: *const fn () void,
    stack: [4096]u8,
    ctx: context.Context,
    data: ?*anyopaque,

    /// Creates a new fiber with the given function and optional data pointer
    pub fn init(func: *const fn () void, data_ptr: ?*anyopaque) Fiber {
        var fiber = Fiber{
            .fn_ptr = func,
            .stack = undefined,
            .ctx = std.mem.zeroes(context.Context),
            .data = data_ptr,
        };

        // Set up stack pointer (stacks grow downwards)
        var sp: [*]u8 = @ptrFromInt(@intFromPtr(&fiber.stack) + 4096);

        // Apply Sys V ABI stack alignment to 16 bytes
        const sp_usize = @intFromPtr(sp);
        const aligned_sp_usize = sp_usize & ~@as(usize, 15);
        sp = @ptrFromInt(aligned_sp_usize);

        // Reserve 128-byte Red Zone (Sys V ABI)
        sp = @ptrFromInt(@intFromPtr(sp) - 128);

        // Set up context to point to fiber function
        fiber.ctx.rip = @ptrCast(@alignCast(@constCast(func)));
        fiber.ctx.rsp = @ptrCast(sp);

        return fiber;
    }

    /// Returns the context of this fiber
    pub fn get_context(self: *Fiber) *context.Context {
        return &self.ctx;
    }
};

// Scheduler class
pub const Scheduler = struct {
    fibers: std.ArrayList(*Fiber),
    allocator: std.mem.Allocator,
    fiber_return_point: context.Context,

    /// Initializes a new scheduler
    pub fn init(allocator: std.mem.Allocator) !Scheduler {
        return Scheduler{
            .fibers = try std.ArrayList(*Fiber).initCapacity(allocator, 0),
            .allocator = allocator,
            .fiber_return_point = std.mem.zeroes(context.Context),
        };
    }

    /// Deinitializes the scheduler
    pub fn deinit(self: *Scheduler) void {
        self.fibers.deinit(self.allocator);
    }

    /// Adds a fiber to the queue
    pub fn spawn(self: *Scheduler, fiber: *Fiber) !void {
        try self.fibers.append(self.allocator, fiber);
    }

    /// Executes all queued fibers until completion
    pub fn do_it(self: *Scheduler) void {
        // Save return point - fibers will jump back here
        _ = context.get(&self.fiber_return_point);

        if (self.fibers.items.len > 0) {
            const fiber_ptr = self.fibers.orderedRemove(0);
            current_fiber_ptr = fiber_ptr;

            // Jump to fiber
            _ = context.set(&fiber_ptr.ctx);
        }
    }

    /// Called by fibers to exit and complete
    pub fn fiber_exit(self: *Scheduler) void {
        current_fiber_ptr = null;
        _ = context.set(&self.fiber_return_point);
    }
};

// Global API functions
pub fn spawn(fiber: *Fiber) !void {
    try global_scheduler.spawn(fiber);
}

pub fn do_it() void {
    global_scheduler.do_it();
}

pub fn fiber_exit() void {
    global_scheduler.fiber_exit();
}

pub fn get_data() ?*anyopaque {
    if (current_fiber_ptr) |fiber| {
        return fiber.data;
    }
    return null;
}

// Example functions
fn func1() void {
    std.debug.print("fiber 1\n", .{});
    fiber_exit();
}

fn func2() void {
    std.debug.print("fiber 2\n", .{});
    fiber_exit();
}

fn func1_with_data() void {
    std.debug.print("fiber 1\n", .{});
    const dp = get_data();
    if (dp) |ptr| {
        const data_ptr = @as(*i32, @ptrCast(@alignCast(ptr)));
        std.debug.print("fiber 1: {}\n", .{data_ptr.*});
        data_ptr.* += 1;
    }
    fiber_exit();
}

fn func2_with_data() void {
    const dp = get_data();
    if (dp) |ptr| {
        const data_ptr = @as(*i32, @ptrCast(@alignCast(ptr)));
        std.debug.print("fiber 2: {}\n", .{data_ptr.*});
    }
    fiber_exit();
}

// Examples
pub fn basic_scheduler_example() void {
    std.debug.print("\n=== Basic Scheduler Example ===\n", .{});

    var f1 = Fiber.init(&func1, null);
    var f2 = Fiber.init(&func2, null);

    spawn(&f1) catch @panic("Failed to spawn f1");
    spawn(&f2) catch @panic("Failed to spawn f2");

    do_it();
}

pub fn data_sharing_example() void {
    std.debug.print("\n=== Data Sharing Example ===\n", .{});

    var d: i32 = 10;
    const dp = &d;

    var f1 = Fiber.init(&func1_with_data, @as(?*anyopaque, @ptrCast(dp)));
    var f2 = Fiber.init(&func2_with_data, @as(?*anyopaque, @ptrCast(dp)));

    spawn(&f1) catch @panic("Failed to spawn f1");
    spawn(&f2) catch @panic("Failed to spawn f2");

    do_it();
}

// Main function
pub fn main() void {
    // Initialize global scheduler
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    global_scheduler = Scheduler.init(allocator) catch @panic("Failed to init scheduler");
    defer global_scheduler.deinit();

    std.debug.print("=== Task 2 Examples ===\n", .{});

    basic_scheduler_example();
    data_sharing_example();

    std.debug.print("\n=== All Task 2 Examples Complete ===\n", .{});
}

// Unit tests
test "fiber initialization" {
    const fiber = Fiber.init(&func1, null);

    // Check that RIP is set
    try std.testing.expect(fiber.ctx.rip != null);

    // Check stack alignment
    const rsp_usize = @intFromPtr(fiber.ctx.rsp);
    try std.testing.expect(rsp_usize % 16 == 0);
}

test "scheduler spawn" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    var fiber = Fiber.init(&func1, null);

    try scheduler.spawn(&fiber);
    try std.testing.expect(scheduler.fibers.items.len == 1);
}

test "get_data returns correct pointer" {
    var data: i32 = 42;
    var fiber = Fiber.init(&func1, @as(?*anyopaque, @ptrCast(&data)));

    // Simulate current fiber
    current_fiber_ptr = &fiber;

    const retrieved = get_data();
    try std.testing.expect(retrieved != null);
    const data_ptr = @as(*i32, @ptrCast(@alignCast(retrieved.?)));
    try std.testing.expect(data_ptr.* == 42);
}
