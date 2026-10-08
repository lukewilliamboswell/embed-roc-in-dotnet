using System.Runtime.InteropServices;

namespace Roc.Hosting;

/// <summary>Owns the native library and enforces the adapter's invocation lifetime.</summary>
internal sealed class NativePlugin : IDisposable
{
    private readonly SafeLibraryHandle _library;
    private readonly nint _entryPoint;
    private readonly object _gate = new();
    private bool _running;
    private bool _disposed;
    // The shim uses an active host context while Roc calls direct linker symbols.
    // A process-wide gate also covers separate wrappers that load the same DLL.
    private static int s_activeRun;

    internal NativePlugin(string path)
    {
        _library = new SafeLibraryHandle(NativeLibrary.Load(path));
        try
        {
            // Cache the address only after the library has an owner. A failed export
            // lookup must release the handle just as a successfully disposed plugin does.
            _entryPoint = NativeLibrary.GetExport(_library.DangerousGetHandle(), "roc_run_app");
        }
        catch
        {
            _library.Dispose();
            throw;
        }
    }

    internal int Run(RocHost host, string[] arguments)
    {
        // The short lock protects this object's state, without holding a managed
        // monitor while arbitrary caller-supplied readers and writers execute.
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_running || Interlocked.CompareExchange(ref s_activeRun, 1, 0) != 0)
                throw new InvalidOperationException("A Roc plugin invocation is already running.");
            _running = true;
        }

        bool acquired = false;
        try
        {
            // Function-pointer calls do not automatically retain a SafeHandle.
            // This reference keeps the library loaded until native execution and
            // every synchronous managed callback have returned.
            _library.DangerousAddRef(ref acquired);
            // Per-run state is disposed before the shared library reference is released.
            using var invocation = new RocInvocation(host);
            return invocation.Run(_entryPoint, arguments);
        }
        finally
        {
            if (acquired)
                _library.DangerousRelease();
            lock (_gate)
                _running = false;
            Volatile.Write(ref s_activeRun, 0);
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_running)
                throw new InvalidOperationException("Cannot unload a Roc plugin during an invocation.");
            if (_disposed)
                return;
            _disposed = true;
            _library.Dispose();
        }
    }

    /// <summary>Pairs NativeLibrary.Load with NativeLibrary.Free, including finalizer cleanup.</summary>
    private sealed class SafeLibraryHandle : SafeHandle
    {
        internal SafeLibraryHandle(nint library) : base(nint.Zero, ownsHandle: true) => SetHandle(library);

        public override bool IsInvalid => handle == 0;

        protected override bool ReleaseHandle()
        {
            NativeLibrary.Free(handle);
            return true;
        }
    }
}
