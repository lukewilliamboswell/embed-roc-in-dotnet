using System.Text;
using Roc.Hosting;

// The CLI chooses console streams and a process exit code. Library loading,
// callbacks, and native lifetimes belong to the reusable Roc.Hosting project.
// Keep redirected streams consistent with the UTF-8 native contract on Windows
// and Linux, independently of the console's default code page.
Console.InputEncoding = Encoding.UTF8;
Console.OutputEncoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

if (args.Length < 1)
{
    Console.Error.WriteLine("Usage: dotnet run --project dotnet-host -- <library-path> [app-arguments...]");
    return 2;
}
try
{
    using var plugin = RocPlugin.Load(args[0]);
    var host = new RocHost(Console.In, Console.Out, Console.Error);
    // The first CLI argument locates the library; the remainder is passed to the
    // Roc application verbatim, without prepending a program or library name.
    return plugin.Run(host, args[1..]);
}
catch (Exception ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}
