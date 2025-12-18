const std = @import("std");
const context = @import("context.zig");

// =============================================================================
// Task 1: Basic Context Switching and Fiber Implementation
// =============================================================================

// Basic context switching example with volatile variable
pub fn context_switch_example() void {
    var x: u32 = 0;
    var c: context.Context = undefined;

    _ = context.get(&c); // Save context here
    std.debug.print("a message\n", .{});
    if (x == 0) {
        x += 1;
        _ = context.set(&c); // Jump back
    }
}

// Fiber function that yields back to main
pub fn foo() void {
    std.debug.print("you called foo\n", .{});
    // Yield back to main instead of exiting
    context.fiber_exit();
}

// Another fiber function
pub fn goo() void {
    std.debug.print("you called goo\n", .{});
    // Yield back to main instead of exiting
    context.fiber_exit();
}

// Example with two fibers
pub fn two_fiber_example() void {

    // Setup for foo
    //--------------------------------------------------------
    // Allocate space for stack
    var data1: [4096]u8 = undefined;

    // Stacks grow downwards
    var sp1: [*]u8 = @ptrFromInt(@intFromPtr(&data1) + 4096);

    // Apply Sys V ABI stack alignment to 16 bytes
    const sp1_usize = @intFromPtr(sp1);
    const aligned_sp1_usize = sp1_usize & ~@as(usize, 15);
    sp1 = @ptrFromInt(aligned_sp1_usize);

    // Reserve 128-byte Red Zone (Sys V ABI)
    sp1 = @ptrFromInt(@intFromPtr(sp1) - 128);

    // Create empty context
    var c1: context.Context = std.mem.zeroes(context.Context);
    c1.rip = @ptrCast(@alignCast(@constCast(&foo))); // Assigned IP to foo
    c1.rsp = @ptrCast(sp1);
    //--------------------------------------------------------

    // Setup for goo
    //--------------------------------------------------------
    // Allocate space for stack
    var data2: [4096]u8 = undefined;

    // Stacks grow downwards
    var sp2: [*]u8 = @ptrFromInt(@intFromPtr(&data2) + 4096);

    // Apply Sys V ABI stack alignment to 16 bytes
    const sp2_usize = @intFromPtr(sp2);
    const aligned_sp2_usize = sp2_usize & ~@as(usize, 15);
    sp2 = @ptrFromInt(aligned_sp2_usize);

    // Reserve 128-byte Red Zone (Sys V ABI)
    sp2 = @ptrFromInt(@intFromPtr(sp2) - 128);

    // Create empty context
    var c2: context.Context = std.mem.zeroes(context.Context);
    c2.rip = @ptrCast(@alignCast(@constCast(&goo))); // Assinged IP to goo
    c2.rsp = @ptrCast(sp2);
    //--------------------------------------------------------

    // Save main context before switching -> Allows fiber_exits to return to main fn
    context.save_main();

    // Jump to foo
    _ = context.set(&c1);

    // Jump to goo
    _ = context.set(&c2);
}

pub fn main() void {
    std.debug.print("Context Switch Example:\n", .{});
    context_switch_example();

    std.debug.print("\nTwo Fiber Example:\n", .{});
    two_fiber_example();
}

// Unit tests

test "fiber stack setup" {
    // Test that stack pointers are properly aligned
    var data: [4096]u8 = undefined;
    var sp: [*]u8 = @ptrFromInt(@intFromPtr(&data) + 4096);
    const sp_usize = @intFromPtr(sp);
    const aligned_sp_usize = sp_usize & ~@as(usize, 15);
    sp = @ptrFromInt(aligned_sp_usize);
    sp = @ptrFromInt(@intFromPtr(sp) - 128);

    // Check alignment
    try std.testing.expect(@intFromPtr(sp) % 16 == 0);
}
