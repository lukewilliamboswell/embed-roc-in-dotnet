using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace Roc.Hosting;

/// <summary>Roots one host and owns its temporary unmanaged UTF-8 transfer buffers.</summary>
/// <remarks>
/// Native execution and its callbacks are synchronous on the calling thread. This
/// keeps the NativeMemory buffer registry local to one run and avoids leaking an
/// unmanaged API into the public plugin abstraction. Roc's own allocations belong
/// to a separate allocator and reference-counting domain inside the Zig adapter.
/// </remarks>
internal sealed unsafe class RocInvocation(RocHost host) : IDisposable
{
    private readonly RocHost _host = host;
    // Track ownership separately from buffer length: a successful empty input and
    // an empty error message can both have a non-null allocation of length zero.
    private readonly HashSet<nint> _buffers = [];

    internal int Run(nint entryPoint, string[] arguments)
    {
        // The GCHandle roots this invocation and its host until the synchronous
        // native call returns. Neither Zig nor Roc retains the callback table.
        GCHandle context = GCHandle.Alloc(this);
        try
        {
            // Arguments stay borrowed by Zig until the call returns. Zig copies
            // them into an owned List(Str), which compiled Roc then consumes.
            var values = new Utf8Buffer[arguments.Length];
            for (int i = 0; i < arguments.Length; i++)
                values[i] = Copy(arguments[i]);

            // UnmanagedCallersOnly static functions need no delegate objects to
            // root; the GCHandle supplies all invocation-specific managed state.
            NativeCallbacks callbacks = new()
            {
                Stdout = &WriteStdout,
                Stderr = &WriteStderr,
                Diagnostic = &WriteDiagnostic,
                Stdin = &ReadStdin,
                Release = &Release,
            };
            var run = (delegate* unmanaged[Cdecl]<Utf8Buffer*, nuint, NativeCallbacks*, nint, int>)entryPoint;
            // Pin the array of descriptors. Each descriptor already points to an
            // unmanaged allocation, so the UTF-8 bytes themselves cannot move.
            fixed (Utf8Buffer* args = values)
                return run(args, (nuint)values.Length, &callbacks, GCHandle.ToIntPtr(context));
        }
        finally
        {
            context.Free();
        }
    }

    /// <summary>Creates an owned UTF-8 buffer to be released by Zig or invocation cleanup.</summary>
    private Utf8Buffer Copy(string text)
    {
        int length = Encoding.UTF8.GetByteCount(text);
        // Even an empty error needs a non-null pointer to distinguish it from success.
        byte* data = (byte*)NativeMemory.Alloc((nuint)Math.Max(1, length));
        if (data == null)
            throw new OutOfMemoryException();
        try
        {
            Encoding.UTF8.GetBytes(text, new Span<byte>(data, length));
            _buffers.Add((nint)data);
            return new Utf8Buffer { Data = data, Length = (nuint)length };
        }
        catch
        {
            NativeMemory.Free(data);
            throw;
        }
    }

    // The context is opaque to native code: only these callbacks interpret it as
    // a GCHandle, and only while Run owns that handle.
    private static RocInvocation Current(nint context) => (RocInvocation)GCHandle.FromIntPtr(context).Target!;
    private static string Decode(byte* data, nuint length) => Encoding.UTF8.GetString(new ReadOnlySpan<byte>(data, checked((int)length)));

    /// <summary>Translates a managed failure into bytes that Zig can copy into a Roc error.</summary>
    private static Utf8Buffer Failure(nint context, Exception exception)
    {
        try
        {
            return Current(context).Copy(exception.Message);
        }
        catch (Exception fatal)
        {
            // No managed exception may unwind through Zig/Roc, including one
            // raised while allocating the error buffer itself.
            Environment.FailFast("Unable to return a managed callback error to Roc.", fatal);
            return default;
        }
    }

    // Every unmanaged entry point catches exceptions before returning to Zig.
    // Output buffers belong to Roc and are borrowed only during this callback;
    // Decode creates a managed string before invoking the caller's writer.
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static Utf8Buffer WriteStdout(nint context, byte* data, nuint length)
    {
        try { Current(context)._host.Output.WriteLine(Decode(data, length)); return default; }
        catch (Exception ex) { return Failure(context, ex); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static Utf8Buffer WriteStderr(nint context, byte* data, nuint length)
    {
        try { Current(context)._host.Error.WriteLine(Decode(data, length)); return default; }
        catch (Exception ex) { return Failure(context, ex); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static Utf8Buffer WriteDiagnostic(nint context, byte* data, nuint length)
    {
        try { Current(context)._host.Error.Write(Decode(data, length)); return default; }
        catch (Exception ex) { return Failure(context, ex); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static Utf8Buffer ReadStdin(nint context, Utf8Buffer* value)
    {
        try
        {
            var invocation = Current(context);
            // This platform deliberately gives EOF and an empty line the same
            // Roc representation. The reader has already removed the line ending.
            *value = invocation.Copy(invocation._host.Input.ReadLine() ?? "");
            return default;
        }
        catch (Exception ex) { return Failure(context, ex); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void Release(nint context, Utf8Buffer buffer)
    {
        try
        {
            if (buffer.Data == null)
                return;
            // Remove before freeing so a repeated release is a fatal ABI violation
            // rather than an unnoticed double free.
            if (!Current(context)._buffers.Remove((nint)buffer.Data))
                throw new InvalidOperationException("Roc released an unknown managed buffer.");
            NativeMemory.Free(buffer.Data);
        }
        catch (Exception fatal)
        {
            Environment.FailFast("Invalid managed buffer release from Roc.", fatal);
        }
    }

    public void Dispose()
    {
        // Argument buffers are borrowed for the whole invocation. Any callback
        // buffers still outstanding are also reclaimed here.
        foreach (nint buffer in _buffers)
            NativeMemory.Free((void*)buffer);
        _buffers.Clear();
    }
}
