pub const c = @cImport({
    @cInclude("context.h");
});

// Assigning C functions
pub const Context = c.struct_Context;
pub const get = c.get_context;
pub const set = c.set_context;
pub const swap = c.swap_context;
