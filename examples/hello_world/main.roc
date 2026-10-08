app [main!] { roc: "nightly-2026-10-04-130536d", pf: platform "../../platform/main.roc" }

import pf.Stdout

## The application entry point required by the selected platform.
## `=>` marks an effectful function; the `!` suffix makes that visible at call sites.
## The `?` operator propagates a write error for the platform to report.
main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str)])
main! = |_args| {
    Stdout.line!("Hello, World!")?
    Ok({})
}
