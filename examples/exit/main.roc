app [main!] { roc: "nightly-2026-10-04-130536d", pf: platform "../../platform/main.roc" }

## Ask the platform to return exit code 42 to the embedding caller.
## Exit is an application result, not a request to terminate the .NET process.
main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| Err(Exit(42))
