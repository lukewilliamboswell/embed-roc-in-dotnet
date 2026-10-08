// This separate executable validates the reusable library through its public
// API. scripts/smoke.roc exercises the user-facing CLI in additional subprocesses.
if (args.Length != 1)
    throw new ArgumentException("Usage: dotnet run --project dotnet-tests -- <effects-library>");

SmokeTests.Check(args[0]);
Console.WriteLine("Managed plugin smoke checks passed");
