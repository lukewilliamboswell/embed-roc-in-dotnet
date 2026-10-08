//! Adapter between the fixed .NET callback ABI and this platform's compiled Roc ABI.
//!
//! Managed code sees UTF-8 byte buffers and a signed exit code. Only this layer
//! handles Roc strings, lists, result layouts, allocation, and owned references.
//! Each invocation is synchronous; callbacks and the opaque context are borrowed
//! until roc_run_app returns and are never retained afterward.

const std = @import("std");
const abi = @import("roc_platform_abi.zig");

pub const std_options: std.Options = .{ .allow_stack_tracing = false };

/// UTF-8 bytes, with a byte count and no required NUL terminator.
///
/// For callback errors, a null pointer means success and a non-null pointer means
/// failure, even when len is zero. Managed input/error buffers must be released
/// through Callbacks.release after their bytes have been copied into Roc values.
pub const Buffer = extern struct { ptr: ?[*]const u8, len: usize };
/// C-compatible callbacks; field order must match dotnet-plugin/NativeAbi.cs.
///
/// Writers borrow Roc's bytes for the callback. The reader returns a separately
/// owned input buffer through its second argument. All four I/O callbacks return
/// a Buffer containing an error, or a null-pointer Buffer on success.
/// Every callback receives the same opaque context supplied by the managed caller.
pub const Callbacks = extern struct {
    write_stdout: *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) Buffer,
    write_stderr: *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) Buffer,
    write_diagnostic: *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) Buffer,
    read_stdin: *const fn (?*anyopaque, *Buffer) callconv(.c) Buffer,
    release: *const fn (?*anyopaque, Buffer) callconv(.c) void,
};
/// Stack-owned state for one invocation, including the Roc helper allocator context.
const Host = struct {
    env: abi.RocEnv,
    // This generated helper context is not the C# RocHost. Compiled Roc uses
    // direct symbols; only our glue helpers receive this allocator/diagnostic context.
    roc_host: abi.RocHost,
    callbacks: *const Callbacks,
    context: ?*anyopaque,
};
// Compiled Roc calls direct symbols without a context parameter, so those symbols
// find the current invocation here. The atomic guard prevents overlapping native
// calls from replacing this stack pointer; .NET adds its own process-wide guard.
var active: ?*Host = null;
var running: std.atomic.Value(bool) = .init(false);

fn current() *Host { return active orelse unreachable; }
fn slice(buffer: Buffer) []const u8 {
    return if (buffer.ptr) |ptr| ptr[0..buffer.len] else "";
}
/// Constructs a Roc-owned Try result, then returns the managed buffer to its owner.
fn result(comptime T: type, value: Buffer, failed: bool) T {
    const h = current();
    defer h.callbacks.release(h.context, value);
    // Initialize padding and the inactive payload too: these generated layouts
    // cross a native ABI, including the MSVC return-value convention on Windows.
    var r = std.mem.zeroInit(T, .{ .tag = .Ok });
    if (failed) r.tag = .Err;
    if (failed) r.payload = .{ .err = abi.RocStr.fromSlice(slice(value), &h.roc_host) };
    return r;
}
/// Implements Host.stdout_line!: consume one owned Roc string and return Try({}, ...).
fn stdoutLine(value: abi.RocStr) callconv(.c) abi.HostStdout_lineResult {
    const h = current();
    // Hosted arguments transfer ownership to us. Keep the string alive while the
    // managed callback borrows its bytes, then release exactly that owned reference.
    defer value.decref(&h.roc_host);
    const bytes = value.asSlice();
    const error_buffer = h.callbacks.write_stdout(h.context, bytes.ptr, bytes.len);
    return result(abi.HostStdout_lineResult, error_buffer, error_buffer.ptr != null);
}
/// Implements Host.stderr_line! with the same owned-argument rule as stdoutLine.
fn stderrLine(value: abi.RocStr) callconv(.c) abi.HostStderr_lineResult {
    const h = current();
    defer value.decref(&h.roc_host);
    const bytes = value.asSlice();
    const error_buffer = h.callbacks.write_stderr(h.context, bytes.ptr, bytes.len);
    return result(abi.HostStderr_lineResult, error_buffer, error_buffer.ptr != null);
}
/// Implements Host.stdin_line!: copy managed input into a Roc-owned result string.
fn stdinLine() callconv(.c) abi.HostStdin_lineResult {
    const h = current();
    var input: Buffer = .{ .ptr = null, .len = 0 };
    const error_buffer = h.callbacks.read_stdin(h.context, &input);
    if (error_buffer.ptr != null) return result(abi.HostStdin_lineResult, error_buffer, true);
    // The callback allocation and the returned Roc string have different owners.
    // Copy first; the managed allocation can then be freed before Roc resumes.
    defer h.callbacks.release(h.context, input);
    var r = std.mem.zeroInit(abi.HostStdin_lineResult, .{ .tag = .Ok });
    r.payload = .{ .ok = abi.RocStr.fromSlice(slice(input), &h.roc_host) };
    return r;
}
// Roc's runtime symbols have no explicit host argument. Adapt them to the helper
// context in the generated glue, using a per-invocation allocator and diagnostics.
fn alloc(len: usize, alignment: usize) callconv(.c) *anyopaque { return abi.DefaultAllocators.rocAlloc(&current().roc_host, len, alignment); }
fn dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void { abi.DefaultAllocators.rocDealloc(&current().roc_host, ptr, alignment); }
fn realloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque { return abi.DefaultAllocators.rocRealloc(&current().roc_host, ptr, len, alignment); }
fn dbg(bytes: [*]const u8, len: usize) callconv(.c) void { abi.DefaultHandlers.rocDbg(&current().roc_host, bytes, len); }
fn expectFailed(bytes: [*]const u8, len: usize) callconv(.c) void { abi.DefaultHandlers.rocExpectFailed(&current().roc_host, bytes, len); }
fn crashed(bytes: [*]const u8, len: usize) callconv(.c) void { abi.DefaultHandlers.rocCrashed(&current().roc_host, bytes, len); }
/// Sends already-formatted runtime diagnostics to managed stderr without adding a newline.
fn diagnostic(_: ?*anyopaque, bytes: []const u8) void {
    const h = current();
    const error_buffer = h.callbacks.write_diagnostic(h.context, bytes.ptr, bytes.len);
    // Diagnostic hooks return no Try value, so a failed diagnostic write cannot
    // become an application error. Release its error buffer without reporting again.
    h.callbacks.release(h.context, error_buffer);
}
/// Roc crashes and failed Roc allocations cannot return to compiled Roc code.
fn fatal(_: ?*anyopaque) noreturn { std.process.exit(1); }
const io_vtable: abi.RocIo.VTable = .{ .writeStderr = diagnostic, .onFatal = fatal };

comptime {
    // These satisfy the platform's hosted declarations and Roc runtime symbols.
    // They are internal linkage details of the final shared library; managed code
    // only resolves the public roc_run_app export.
    @export(&stdoutLine, .{ .name = "roc_stdout_line", .visibility = .hidden });
    @export(&stderrLine, .{ .name = "roc_stderr_line", .visibility = .hidden });
    @export(&stdinLine, .{ .name = "roc_stdin_line", .visibility = .hidden });
    @export(&alloc, .{ .name = "roc_alloc", .visibility = .hidden });
    @export(&dealloc, .{ .name = "roc_dealloc", .visibility = .hidden });
    @export(&realloc, .{ .name = "roc_realloc", .visibility = .hidden });
    @export(&dbg, .{ .name = "roc_dbg", .visibility = .hidden });
    @export(&expectFailed, .{ .name = "roc_expect_failed", .visibility = .hidden });
    @export(&crashed, .{ .name = "roc_crashed", .visibility = .hidden });
}

/// Runs the platform's provided roc_main entry point with UTF-8 application arguments.
///
/// args, callbacks, and context are borrowed until return. Each argument is copied
/// into a Roc Str, and ownership of the resulting List(Str) transfers to roc_main;
/// the host must not decref that transferred list after the call.
///
/// Returns the platform's signed application exit code. A direct native caller
/// receives -2 when this adapter is already active; this value is also a possible
/// application exit code. The managed API rejects overlap before entering native code.
pub export fn roc_run_app(args: [*]const Buffer, count: usize, callbacks: *const Callbacks, context: ?*anyopaque) callconv(.c) i32 {
    if (running.swap(true, .acq_rel)) return -2;
    defer running.store(false, .release);
    var h: Host = undefined;
    h.callbacks = callbacks;
    h.context = context;
    // A helper context per run is not an arena. page_allocator supplies native
    // blocks that Roc releases via reference counting and roc_dealloc, without
    // an automatic bulk reset when this stack context goes out of scope.
    h.env = .{ .allocator = std.heap.page_allocator, .roc_io = .{ .ctx = null, .vtable = &io_vtable } };
    h.roc_host = abi.makeRocHost(&h.env);
    active = &h;
    defer active = null;
    const list = abi.RocList(abi.RocStr).allocate(count, &h.roc_host);
    if (list.elements_ptr) |ptr| {
        for (args[0..count], ptr[0..count]) |arg, *slot| slot.* = abi.RocStr.fromSlice(slice(arg), &h.roc_host);
    }
    return abi.roc_main(list);
}
