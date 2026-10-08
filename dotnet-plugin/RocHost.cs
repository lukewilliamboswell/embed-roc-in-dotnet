namespace Roc.Hosting;

/// <summary>Supplies managed streams for a Roc invocation's standard I/O effects.</summary>
/// <remarks>
/// The streams are dependencies supplied by the embedding application, so the same plugin
/// can use console streams, in-memory streams, or custom readers and writers on each run.
/// The caller owns all three streams and must keep them usable until the synchronous run ends.
/// This object neither closes streams nor changes their flushing or newline policies.
/// </remarks>
public sealed class RocHost
{
    /// <summary>The reader used by the platform's <c>Stdin.line!</c> effectful function.</summary>
    /// <remarks><see cref="TextReader.ReadLine"/> supplies a line without its terminator. End of input becomes an empty Roc string.</remarks>
    public TextReader Input { get; }
    /// <summary>The writer used by the platform's <c>Stdout.line!</c> effectful function.</summary>
    /// <remarks>Each call uses <see cref="TextWriter.WriteLine(string)"/>, including the writer's configured newline.</remarks>
    public TextWriter Output { get; }
    /// <summary>The writer used by <c>Stderr.line!</c> and Roc runtime diagnostics.</summary>
    /// <remarks>Application lines use <see cref="TextWriter.WriteLine(string)"/>; diagnostics use <see cref="TextWriter.Write(string)"/>.</remarks>
    public TextWriter Error { get; }

    /// <summary>Creates a host backed by caller-owned streams.</summary>
    /// <param name="input">The reader for line-oriented input.</param>
    /// <param name="output">The writer for application output.</param>
    /// <param name="error">The writer for application errors and runtime diagnostics.</param>
    /// <exception cref="ArgumentNullException">Any stream is null.</exception>
    public RocHost(TextReader input, TextWriter output, TextWriter error)
    {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(output);
        ArgumentNullException.ThrowIfNull(error);
        Input = input;
        Output = output;
        Error = error;
    }
}
