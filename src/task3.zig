const std = @import("std");
const context = @import("context.zig");

// =============================================================================
// Task 3: Thread Pool Implementation using Cooperative Fibers with Yields
// Executes multiple instructions concurrently using cooperative fibers with yield and data sharing capabilities
// =============================================================================

// Import Fiber and Scheduler from Task 2
const task2 = @import("task2.zig");
const Fiber = task2.Fiber;
const Scheduler = task2.Scheduler;

// Global scheduler instance (from task2)
var scheduler_instance: *Scheduler = undefined;
var current_fiber: ?*Fiber = null;

// ThreadPool class - simplified for cooperative fibers
pub const ThreadPool = struct {
    fibers_: std.ArrayList(*Fiber),
    yielded_fibers: std.ArrayList(*Fiber),
    context_: context.Context,
    allocator: std.mem.Allocator,

    /// Constructor
    pub fn init(allocator: std.mem.Allocator) !ThreadPool {
        return ThreadPool{
            .fibers_ = try std.ArrayList(*Fiber).initCapacity(allocator, 10),
            .yielded_fibers = try std.ArrayList(*Fiber).initCapacity(allocator, 10),
            .context_ = undefined,
            .allocator = allocator,
        };
    }

    /// Destructor
    pub fn deinit(self: *ThreadPool) void {
        self.fibers_.deinit(self.allocator);
        self.yielded_fibers.deinit(self.allocator);
    }

    /// Spawn a fiber (task) on the pool
    pub fn spawn(self: *ThreadPool, f: *Fiber) !void {
        try self.fibers_.append(self.allocator, f);
    }

    /// Cooperatively yields the current fiber back to the thread pool
    pub fn fiber_yield(self: *ThreadPool) void {
        if (current_fiber) |fiber| {
            // Re-queue the current fiber
            self.yielded_fibers.append(std.heap.page_allocator, fiber) catch @panic("Failed to yield fiber");

            // Swap context: save current to fiber, switch to thread pool
            _ = context.swap(&fiber.context, &self.context_);
        }
    }

    /// Terminates the current fiber and returns control to the thread pool
    pub fn fiber_exit(self: *ThreadPool) void {
        if (current_fiber) |_| {
            // Clear current fiber (it's done)
            current_fiber = null;

            // Switch back to thread pool context (no need to save current)
            _ = context.set(&self.context_);
        }
    }

    /// Run the thread pool
    pub fn run(self: *ThreadPool) !void {
        // Set global thread pool instance
        thread_pool_instance = self;

        // Save thread pool context
        _ = context.get(&self.context_);

        // Run the scheduler with yield support
        self.do_it_with_yields();
    }

    /// Runs the cooperative scheduler that handles both new and yielded fibers
    fn do_it_with_yields(self: *ThreadPool) void {
        while (self.fibers_.items.len > 0 or self.yielded_fibers.items.len > 0) {
            // Process fibers in order: new fibers first, then yielded ones
            if (self.fibers_.items.len > 0) {
                const f = self.fibers_.orderedRemove(0);
                current_fiber = f;
                const c = f.get_context();
                _ = context.set(c);
            } else if (self.yielded_fibers.items.len > 0) {
                const f = self.yielded_fibers.orderedRemove(0);
                current_fiber = f;
                const c = f.get_context();
                _ = context.set(c);
            }
        }
    }
};

// Global thread pool instance for yield support
var thread_pool_instance: ?*ThreadPool = null;

// Global API for fiber operations
/// Cooperatively yields the current fiber
pub fn yield() void {
    std.debug.print("Global yield called\n", .{});
    if (thread_pool_instance) |tp| {
        tp.fiber_yield();
    }
}

/// Retrieves the data pointer associated with the current fiber
pub fn get_data() ?*anyopaque {
    if (current_fiber) |f| {
        return f.get_data();
    }
    return null;
}

// Example task functions
fn task1() void {
    std.debug.print("Instruction 1 executing\n", .{});
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

fn task2_func() void {
    std.debug.print("Instruction 2 executing\n", .{});
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

fn task3_func() void {
    std.debug.print("Instruction 3 executing\n", .{});
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

// Yield demonstration functions
fn f1() void {
    std.debug.print("fiber 1 before\n", .{});
    yield();
    std.debug.print("fiber 1 after\n", .{});
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

fn f2() void {
    std.debug.print("fiber 2\n", .{});
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

// Data sharing with yield example
const SharedData = struct {
    value: i32,
};

fn producer() void {
    const data = get_data();
    if (data) |ptr| {
        const shared = @as(*SharedData, @ptrCast(@alignCast(ptr)));
        shared.value = 42;
        std.debug.print("Producer: set value to {}\n", .{shared.value});
        yield(); // Yield to let consumer run
        std.debug.print("Producer: value is now {}\n", .{shared.value});
    }
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

fn consumer() void {
    yield(); // Let producer run first
    const data = get_data();
    if (data) |ptr| {
        const shared = @as(*SharedData, @ptrCast(@alignCast(ptr)));
        std.debug.print("Consumer: read value {}\n", .{shared.value});
        shared.value += 10;
        std.debug.print("Consumer: modified value to {}\n", .{shared.value});
    }
    if (thread_pool_instance) |tp| {
        tp.fiber_exit();
    }
}

// Main function
pub fn main() void {

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: Basic thread pool
    std.debug.print("\n--- Example 1: Basic Thread Pool ---\n", .{});
    {
        var pool = ThreadPool.init(allocator) catch @panic("Failed to init thread pool");
        defer pool.deinit();

        var t1 = Fiber.init(allocator, &task1, null) catch @panic("Failed to create task1");
        defer t1.deinit(allocator);
        var t2 = Fiber.init(allocator, &task2_func, null) catch @panic("Failed to create task2");
        defer t2.deinit(allocator);
        var t3 = Fiber.init(allocator, &task3_func, null) catch @panic("Failed to create task3");
        defer t3.deinit(allocator);

        pool.spawn(&t1) catch @panic("Failed to spawn task1");
        pool.spawn(&t2) catch @panic("Failed to spawn task2");
        pool.spawn(&t3) catch @panic("Failed to spawn task3");

        pool.run() catch @panic("Failed to run thread pool");
    }

    // Example 2: Yield demonstration (from pseudocode)
    std.debug.print("\n--- Example 2: Fiber Yield ---\n", .{});
    {
        var pool = ThreadPool.init(allocator) catch @panic("Failed to init thread pool");
        defer pool.deinit();
        thread_pool_instance = &pool;

        var fiber1 = Fiber.init(allocator, &f1, null) catch @panic("Failed to create f1");
        defer fiber1.deinit(allocator);
        var fiber2 = Fiber.init(allocator, &f2, null) catch @panic("Failed to create f2");
        defer fiber2.deinit(allocator);

        pool.spawn(&fiber1) catch @panic("Failed to spawn f1");
        pool.spawn(&fiber2) catch @panic("Failed to spawn f2");

        pool.run() catch @panic("Failed to run thread pool");
    }

    // Example 3: Data sharing with yield
    std.debug.print("\n--- Example 3: Data Sharing with Yield ---\n", .{});
    {
        var pool = ThreadPool.init(allocator) catch @panic("Failed to init thread pool");
        defer pool.deinit();
        thread_pool_instance = &pool;

        var shared_data = SharedData{ .value = 0 };

        var prod = Fiber.init(allocator, &producer, @as(?*anyopaque, @ptrCast(&shared_data))) catch @panic("Failed to create producer");
        defer prod.deinit(allocator);
        var cons = Fiber.init(allocator, &consumer, @as(?*anyopaque, @ptrCast(&shared_data))) catch @panic("Failed to create consumer");
        defer cons.deinit(allocator);

        pool.spawn(&prod) catch @panic("Failed to spawn producer");
        pool.spawn(&cons) catch @panic("Failed to spawn consumer");

        pool.run() catch @panic("Failed to run thread pool");
    }
}
