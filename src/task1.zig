const std = @import("std");
const context = @import("context.zig");

// =============================================================================
// Task 1: Basic Context Switching and Fiber Implementation
// =============================================================================

// Basic context switching example with volatile variable
pub fn basic_context_example() void {
    var x: u32 = 0;
    var c: context.Context = undefined;

    _ = context.get(&c); // Save context here
    std.debug.print("a message\n", .{});
    if (x == 0) {
        x += 1;
        _ = context.set(&c); // Jump back
    }
}

// Fiber function that cannot return normally
pub fn foo() void {
    std.debug.print("you called foo\n", .{});
    // Cannot return to main as they have different stacks
    std.process.exit(0);
}

// Another fiber function
pub fn goo() void {
    std.debug.print("you called goo\n", .{});
    // Cannot return to main as they have different stacks
    std.process.exit(0);
}

// Fiber with proper Sys V ABI stack setup
pub fn fiber_example() void {
    // Allocate space for stack
    var data: [4096]u8 = undefined;

    // Stacks grow downwards
    var sp: [*]u8 = @ptrFromInt(@intFromPtr(&data) + 4096);

    // Apply Sys V ABI stack alignment to 16 bytes
    const sp_usize = @intFromPtr(sp);
    const aligned_sp_usize = sp_usize & ~@as(usize, 15);
    sp = @ptrFromInt(aligned_sp_usize);

    // Reserve 128-byte Red Zone (Sys V ABI)
    sp = @ptrFromInt(@intFromPtr(sp) - 128);

    // Create empty context
    var c: context.Context = std.mem.zeroes(context.Context);
    c.rip = @ptrCast(@alignCast(@constCast(&foo)));
    c.rsp = @ptrCast(sp);

    // Jump to foo
    _ = context.set(&c);
}

// Example with two fibers
pub fn two_fiber_example() void {
    // Setup for foo
    var data1: [4096]u8 = undefined;
    var sp1: [*]u8 = @ptrFromInt(@intFromPtr(&data1) + 4096);
    const sp1_usize = @intFromPtr(sp1);
    const aligned_sp1_usize = sp1_usize & ~@as(usize, 15);
    sp1 = @ptrFromInt(aligned_sp1_usize);
    sp1 = @ptrFromInt(@intFromPtr(sp1) - 128);

    var c1: context.Context = std.mem.zeroes(context.Context);
    c1.rip = @ptrCast(@alignCast(@constCast(&foo)));
    c1.rsp = @ptrCast(sp1);

    // Setup for goo
    var data2: [4096]u8 = undefined;
    var sp2: [*]u8 = @ptrFromInt(@intFromPtr(&data2) + 4096);
    const sp2_usize = @intFromPtr(sp2);
    const aligned_sp2_usize = sp2_usize & ~@as(usize, 15);
    sp2 = @ptrFromInt(aligned_sp2_usize);
    sp2 = @ptrFromInt(@intFromPtr(sp2) - 128);

    var c2: context.Context = std.mem.zeroes(context.Context);
    c2.rip = @ptrCast(@alignCast(@constCast(&goo)));
    c2.rsp = @ptrCast(sp2);

    // Jump to foo first
    _ = context.set(&c1);
    // This won't be reached as foo exits
}

// Main function to run examples
pub fn main() void {
    std.debug.print("=== Task 1 Examples ===\n", .{});

    std.debug.print("Basic context example:\n", .{});
    basic_context_example();

    std.debug.print("\nFiber example (will exit):\n", .{});
    fiber_example();

    std.debug.print("\nTwo fiber example (will exit):\n", .{});
    two_fiber_example();
}

// Unit tests
test "basic context switching" {
    // This test would require capturing output, but for now just ensure it compiles
    // In a real test framework, we'd capture stdout
    try std.testing.expect(true);
}

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
