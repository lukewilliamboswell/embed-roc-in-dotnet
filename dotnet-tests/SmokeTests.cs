using Roc.Hosting;

/// <summary>Exercises managed embedding behavior against the compiled effects application.</summary>
internal static class SmokeTests
{
    private sealed class ThrowingReader : StringReader
    {
        public ThrowingReader() : base("") { }
        public override string? ReadLine() => throw new IOException("managed read failed");
    }

    private sealed class ThrowingWriter : StringWriter
    {
        public override void WriteLine(string? value) => throw new IOException("managed write failed");
    }

    // A writer is user code executed inside a native callback. Calling Run here
    // checks that recursive entry fails before the active native host is replaced.
    private sealed class ReentrantWriter(Action onWrite) : StringWriter
    {
        public override void WriteLine(string? value)
        {
            onWrite();
            base.WriteLine(value);
        }
    }

    private sealed class BlockingWriter(ManualResetEventSlim entered, ManualResetEventSlim resume) : StringWriter
    {
        public override void WriteLine(string? value)
        {
            entered.Set();
            if (!resume.Wait(TimeSpan.FromSeconds(10)))
                throw new TimeoutException("Concurrent invocation check timed out");
            base.WriteLine(value);
        }
    }

    internal static void Check(string library)
    {
        using var plugin = RocPlugin.Load(library);
        using var output = new StringWriter();
        using var error = new StringWriter();
        using var input = new StringReader("héllo 🚀\n");
        var host = new RocHost(input, output, error);

        Require(plugin.Run(host, "α", "β") == 0, "Unexpected exit code");
        Require(plugin.Run(host, "", "") == 0 && plugin.Run(host) == 0, "Repeated run failed");
        Contains(output, "args: α|β" + Environment.NewLine);
        Contains(output, "input: héllo 🚀" + Environment.NewLine);
        Contains(output, "args: |" + Environment.NewLine);
        Contains(output, "input: " + Environment.NewLine);
        Contains(error, "stderr: café 🚀" + Environment.NewLine);

        // The loaded plugin can be used with a different host on every invocation.
        // Each character needs multiple UTF-8 bytes, exposing both byte/character
        // count mistakes and accidental fixed-size input or argument buffers.
        string longValue = new('界', 20000);
        output.GetStringBuilder().Clear();
        using var longInput = new StringReader(longValue + "\n");
        Require(plugin.Run(new RocHost(longInput, output, error), longValue) == 0, "Long input failed");
        Contains(output, "args: " + longValue + Environment.NewLine);
        Contains(output, "input: " + longValue + Environment.NewLine);

        int rejected = 0;
        using var reentrant = new ReentrantWriter(() =>
        {
            Throws<InvalidOperationException>(() => plugin.Run(host));
            rejected++;
        });
        Require(plugin.Run(new RocHost(TextReader.Null, reentrant, error)) == 0 && rejected > 0,
            "Recursive invocation was not rejected");

        // The effects app propagates Try errors with ?. The platform prints an
        // unhandled error and maps it to -1; no exception crosses native frames.
        using var readerFailure = new ThrowingReader();
        using var writerFailure = new ThrowingWriter();
        error.GetStringBuilder().Clear();
        Require(plugin.Run(new RocHost(readerFailure, output, error)) == -1, "stdin failure did not become a Roc error");
        Contains(error, "managed read failed");
        Require(plugin.Run(new RocHost(TextReader.Null, writerFailure, error)) == -1, "stdout failure did not become a Roc error");
        Contains(error, "managed write failed");
        Require(plugin.Run(new RocHost(TextReader.Null, output, writerFailure)) == -1, "stderr failure did not become a Roc error");

        CheckConcurrentRun(plugin, host, library);
        Throws<ArgumentNullException>(() => plugin.Run(null!));
        Throws<ArgumentNullException>(() => plugin.Run(host, (string[])null!));
        Throws<ArgumentException>(() => plugin.Run(host, new string[] { null! }));

        // Dispose is idempotent, and the plugin never disposes caller-owned streams.
        plugin.Dispose();
        plugin.Dispose();
        Throws<ObjectDisposedException>(() => plugin.Run(host));
        output.Write("stream remains open");
        error.Write("stream remains open");
        _ = input.ReadLine();

        // Unloading and loading again must leave native and managed guards usable.
        using var reloaded = RocPlugin.Load(library);
        Require(reloaded.Run(new RocHost(TextReader.Null, TextWriter.Null, TextWriter.Null)) == 0,
            "Plugin did not run after reloading");
    }

    /// <summary>Holds a real callback open while competing runs and disposal are attempted.</summary>
    private static void CheckConcurrentRun(RocPlugin plugin, RocHost host, string library)
    {
        using var entered = new ManualResetEventSlim();
        using var resume = new ManualResetEventSlim();
        using var output = new BlockingWriter(entered, resume);
        // Two wrappers may share one underlying OS library handle and native globals.
        using var second = RocPlugin.Load(library);
        Task<int> run = Task.Run(() => plugin.Run(new RocHost(TextReader.Null, output, TextWriter.Null)));
        try
        {
            Require(entered.Wait(TimeSpan.FromSeconds(10)), "Invocation did not reach managed stdout");
            Throws<InvalidOperationException>(() => plugin.Run(host));
            Throws<InvalidOperationException>(() => second.Run(host));
            Throws<InvalidOperationException>(plugin.Dispose);
        }
        finally
        {
            resume.Set();
            Require(run.GetAwaiter().GetResult() == 0, "Original invocation failed");
        }
        Require(second.Run(host) == 0, "A rejected invocation left the plugin locked");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }

    private static void Contains(StringWriter writer, string expected) =>
        Require(writer.ToString().Contains(expected, StringComparison.Ordinal), $"Missing output: {expected}");

    private static void Throws<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new InvalidOperationException($"Expected {typeof(T).Name}");
    }
}
