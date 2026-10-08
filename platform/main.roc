# The app implements `requires`; `provides` exposes compiled Roc functions to
# the host; `hosted` binds effectful declarations to host-implemented symbols.
# The public Roc API is Stdout, Stderr, and Stdin. Host stays private to the platform.
platform ""
    requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
    exposes [Stdout, Stderr, Stdin]
    packages { roc: "nightly-2026-10-04-130536d" }
    provides { "roc_main": main_for_host! }
    hosted {
        "roc_stderr_line": Host.stderr_line!,
        "roc_stdin_line": Host.stdin_line!,
        "roc_stdout_line": Host.stdout_line!,
    }
    # Roc links the prebuilt adapter with the compiled app into one shared library.
    # The .NET host resolves roc_run_app; roc_main is the adapter's internal Roc entry point.
    targets: {
        inputs_dir: "targets/",
        x64musl: { inputs: ["libhost.a", app], output: Shared, exports: ["roc_run_app"] },
        x64win: { inputs: ["host.lib", app], output: Shared, exports: ["roc_run_app"] },
    }

import Stdout
import Stderr
import Stdin
import Host

## Translate the application's Try result into this platform's signed exit code.
##
## Ok({}) means 0, Exit(code) preserves code, and another unhandled error means -1.
## Printing that error is best-effort: a failing stderr writer must not cause a loop.
main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(Exit(code)) => code
        Err(other) => {
            _ = Stderr.line!("ERROR: ${Str.inspect(other)}")
            -1
        }
    }
}
