const std = @import("std");
const context = @import("context.zig");

// =============================================================================
// Task 2: Fiber Class Implementation with Yield Support
// =============================================================================

// Fiber class
pub const Fiber = struct {
    fn_ptr: *const fn () void,
    context: context.Context,
    stack: []u8,
    stack_size: usize,
    stack_bottom: [*]u8,
    stack_top: [*]u8,
    data: ?*anyopaque,

    /// Creates a new fiber with the given function
    pub fn init(allocator: std.mem.Allocator, func: *const fn () void, data: ?*anyopaque) !Fiber {
        const stack_size = 8192;
        var stack = try allocator.alloc(u8, stack_size);

        var fiber = Fiber{
            .fn_ptr = func,
            .context = undefined,
            .stack = stack,
            .stack_size = stack_size,
            .stack_bottom = undefined,
            .stack_top = undefined,
            .data = data,
        };

        // Set up stack pointer (stacks grow downwards)
        var sp: [*]u8 = @ptrFromInt(@intFromPtr(&stack[stack_size - 1]) + 1);

        // Apply Sys V ABI stack alignment to 16 bytes
        const sp_usize = @intFromPtr(sp);
        const aligned_sp_usize = sp_usize & ~@as(usize, 15);
        sp = @ptrFromInt(aligned_sp_usize);

        // Reserve 128-byte Red Zone (Sys V ABI)
        sp = @ptrFromInt(@intFromPtr(sp) - 128);

        // Set up stack pointers
        fiber.stack_bottom = @ptrCast(&stack[0]);
        fiber.stack_top = sp;

        // Save current context to get preserved registers
        var temp_context: context.Context = undefined;
        _ = context.get(&temp_context);

        // Set up context to point to fiber function
        fiber.context.rip = @ptrCast(@alignCast(@constCast(func)));
        fiber.context.rsp = @ptrCast(sp);
        // Copy preserved registers from current context
        fiber.context.rbx = temp_context.rbx;
        fiber.context.rbp = temp_context.rbp;
        fiber.context.r12 = temp_context.r12;
        fiber.context.r13 = temp_context.r13;
        fiber.context.r14 = temp_context.r14;
        fiber.context.r15 = temp_context.r15;

        return fiber;
    }

    /// Deinitializes the fiber
    pub fn deinit(self: *Fiber, allocator: std.mem.Allocator) void {
        allocator.free(self.stack);
    }

    /// Returns the context of this fiber
    pub fn get_context(self: *Fiber) *context.Context {
        return &self.context;
    }

    /// Returns the data pointer of this fiber
    pub fn get_data(self: *const Fiber) ?*anyopaque {
        return self.data;
    }

    /// Yields control back to the specified context (used by schedulers)
    pub fn yield(self: *Fiber, return_context: *context.Context) void {
        std.debug.print("Fiber yielding...\n", .{});
        // Save current context
        _ = context.get(&self.context);

        // Return to the specified context
        _ = context.set(return_context);
    }
};

// Scheduler class
pub const Scheduler = struct {
    fibers_: std.ArrayList(*Fiber),
    context_: context.Context,
    allocator: std.mem.Allocator,

    /// Constructor
    pub fn init(allocator: std.mem.Allocator) !Scheduler {
        return Scheduler{
            .fibers_ = try std.ArrayList(*Fiber).initCapacity(allocator, 0),
            .context_ = undefined,
            .allocator = allocator,
        };
    }

    /// Destructor
    pub fn deinit(self: *Scheduler) void {
        self.fibers_.deinit(self.allocator);
    }

    /// Spawns a fiber
    pub fn spawn(self: *Scheduler, f: *Fiber) void {
        self.fibers_.append(self.allocator, f) catch @panic("Failed to spawn fiber");
    }

    /// Runs the scheduler
    pub fn do_it(self: *Scheduler) void {
        // Save scheduler context
        _ = context.get(&self.context_);

        // Process fibers
        while (self.fibers_.items.len > 0) {
            var f = self.fibers_.orderedRemove(0);
            current_fiber = f;
            const c = f.get_context();
            _ = context.set(c);
        }
    }

    /// Fiber exit
    pub fn fiber_exit(self: *Scheduler) void {
        _ = context.set(&self.context_);
    }
};

// Global scheduler instance
pub var scheduler_instance: *Scheduler = undefined;

// Global current fiber
pub var current_fiber: ?*Fiber = null;

/// Global get_data function
pub fn get_data() ?*anyopaque {
    if (current_fiber) |f| {
        return f.get_data();
    }
    return null;
}

// Print incremented dp value
fn func1() void {
    const dp = get_data();
    if (dp) |ptr| {
        const data_ptr = @as(*i32, @ptrCast(@alignCast(ptr)));
        std.debug.print("fiber 1: {}\n", .{data_ptr.*});
        data_ptr.* += 1;
    }
    scheduler_instance.fiber_exit();
}

// Print current dp value
fn func2() void {
    const dp = get_data();
    if (dp) |ptr| {
        const data_ptr = @as(*i32, @ptrCast(@alignCast(ptr)));
        std.debug.print("fiber 2: {}\n", .{data_ptr.*});
    }
    scheduler_instance.fiber_exit();
}

// Main function
pub fn main() void {

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Set s to be scheduler
    var s = Scheduler.init(allocator) catch @panic("Failed to init scheduler");
    defer s.deinit();

    // Set global scheduler instance
    scheduler_instance = &s;

    // Set d to 10
    var d: i32 = 10;
    const dp = &d;

    // Set f2 to be fiber with func2, dp
    var f2 = Fiber.init(allocator, &func2, @as(?*anyopaque, @ptrCast(dp))) catch @panic("Failed to create fiber f2");
    defer f2.deinit(allocator);

    // Set f1 to be fiber with func1, dp
    var f1 = Fiber.init(allocator, &func1, @as(?*anyopaque, @ptrCast(dp))) catch @panic("Failed to create fiber f1");
    defer f1.deinit(allocator);

    // Call s method spawn with address of f1
    s.spawn(&f1);

    // Call s method spawn with address of f2
    s.spawn(&f2);

    // Call s method do_it
    s.do_it();

    std.debug.print("Scheduler finished\n", .{});
}

// Unit tests
test "fiber initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fiber = try Fiber.init(allocator, &func1, null);
    defer fiber.deinit(allocator);

    // Check that RIP is set
    try std.testing.expect(fiber.context.rip != null);

    // Check stack alignment
    const rsp_usize = @intFromPtr(fiber.context.rsp);
    try std.testing.expect(rsp_usize % 16 == 0);
}
