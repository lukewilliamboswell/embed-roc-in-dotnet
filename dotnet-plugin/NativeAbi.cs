using System.Runtime.InteropServices;

namespace Roc.Hosting;

/// <summary>The C-compatible UTF-8 buffer shared with <c>host-shim/host.zig</c>.</summary>
/// <remarks>
/// Field order, pointer width, and C calling convention are part of the fixed ABI.
/// Length counts bytes without a NUL terminator; embedded NULs are ordinary bytes.
/// These buffers carry bytes between managed code and Zig. Roc string layouts and
/// reference counts remain entirely inside the adapter.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct Utf8Buffer
{
    public byte* Data;
    public nuint Length;
}

/// <summary>Callbacks installed for the duration of one synchronous native invocation.</summary>
/// <remarks>
/// Every callback receives the invocation's opaque GCHandle context. Zig neither
/// retains this stack-allocated table nor invokes its functions after returning.
/// The declaration order must match <c>Callbacks</c> in <c>host-shim/host.zig</c>.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeCallbacks
{
    // Write callbacks borrow their inputs. A null returned pointer means success;
    // a non-null buffer contains an error and is freed by Release after Zig copies it.
    public delegate* unmanaged[Cdecl]<nint, byte*, nuint, Utf8Buffer> Stdout;
    public delegate* unmanaged[Cdecl]<nint, byte*, nuint, Utf8Buffer> Stderr;
    // Diagnostics already include any necessary line breaks. Their error buffers
    // are released by Zig, but are not returned to the application's Try result.
    public delegate* unmanaged[Cdecl]<nint, byte*, nuint, Utf8Buffer> Diagnostic;
    // Stdin writes a separately owned input buffer through its out pointer and
    // returns a null error pointer on success. EOF is successful empty input.
    public delegate* unmanaged[Cdecl]<nint, Utf8Buffer*, Utf8Buffer> Stdin;
    // Zig calls Release after copying input/error bytes into a Roc value. Only
    // buffers allocated by this invocation may be returned here; null is harmless.
    public delegate* unmanaged[Cdecl]<nint, Utf8Buffer, void> Release;
}
