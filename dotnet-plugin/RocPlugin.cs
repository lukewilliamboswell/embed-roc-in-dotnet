namespace Roc.Hosting;

/// <summary>Loads and runs a Roc application built for this demonstration's platform.</summary>
/// <remarks>
/// The shared library contains both compiled Roc code and the Zig platform adapter.
/// This class owns that library until disposal; it does not own the streams supplied
/// through <see cref="RocHost"/>. Its contract is synchronous: arguments and standard
/// I/O enter the application, and a signed exit code returns when execution finishes.
/// </remarks>
public sealed class RocPlugin : IDisposable
{
    private readonly NativePlugin _native;

    private RocPlugin(NativePlugin native) => _native = native;

    /// <summary>Loads a shared library and resolves its <c>roc_run_app</c> entry point.</summary>
    /// <param name="libraryPath">A relative or absolute path to the built Roc shared library.</param>
    /// <returns>A plugin whose native library remains loaded until disposal.</returns>
    /// <exception cref="ArgumentNullException">The path is null.</exception>
    /// <exception cref="ArgumentException">The path is empty or whitespace.</exception>
    /// <exception cref="DllNotFoundException">The native library cannot be loaded.</exception>
    /// <exception cref="BadImageFormatException">The library has an incompatible format or architecture.</exception>
    /// <exception cref="EntryPointNotFoundException">The library does not export <c>roc_run_app</c>.</exception>
    /// <remarks>
    /// The path is resolved relative to the current working directory. The export must
    /// implement this platform's exact ABI; locating the name alone does not verify compatibility.
    /// Loading performs no Roc invocation.
    /// </remarks>
    public static RocPlugin Load(string libraryPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(libraryPath);
        return new RocPlugin(new NativePlugin(Path.GetFullPath(libraryPath)));
    }

    /// <summary>Runs the application synchronously and returns its signed exit code.</summary>
    /// <param name="host">The input, output, and error streams to use for this invocation.</param>
    /// <param name="arguments">Application arguments, without a program or library name.</param>
    /// <returns>
    /// Zero for <c>Ok({})</c>, the application's signed code for <c>Err(Exit(code))</c>,
    /// or -1 when an unhandled Roc error reaches the platform entry point.
    /// </returns>
    /// <exception cref="ArgumentNullException">The host or argument array is null.</exception>
    /// <exception cref="ArgumentException">An argument is null.</exception>
    /// <exception cref="ObjectDisposedException">The plugin has been disposed.</exception>
    /// <exception cref="InvalidOperationException">Another invocation is active, including a recursive call.</exception>
    /// <remarks>
    /// Host streams belong to the caller and remain open. Runs may be repeated with different
    /// hosts. Arguments are encoded as UTF-8 and copied into Roc values by the adapter.
    /// Callbacks execute on the calling thread before this method returns; no callback or
    /// host context is retained afterward. This demonstration permits one invocation at a
    /// time across the process and rejects concurrent or recursive calls even through another
    /// plugin instance. Managed I/O exceptions become Roc <c>Try</c> errors, which the
    /// application can handle. Roc crashes and Roc allocation failures terminate the process.
    /// </remarks>
    public int Run(RocHost host, params string[] arguments)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(arguments);
        foreach (string argument in arguments)
            if (argument is null)
                throw new ArgumentException("Arguments cannot contain null strings.", nameof(arguments));

        return _native.Run(host, arguments);
    }

    /// <summary>Releases this plugin's native library handle.</summary>
    /// <exception cref="InvalidOperationException">This plugin is currently running.</exception>
    /// <remarks>
    /// Repeated disposal is harmless. Disposal leaves caller-owned host streams open and
    /// prevents subsequent invocations. It does not cancel or wait for an active invocation.
    /// </remarks>
    public void Dispose() => _native.Dispose();
}
