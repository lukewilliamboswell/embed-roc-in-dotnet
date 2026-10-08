app [main!] { roc: "nightly-2026-10-04-130536d", pf: platform "../../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Stdin

## Exercise the arguments and all three managed standard I/O implementations.
## Arguments contain exactly the strings supplied to RocPlugin.Run, with no program name.
## Each `?` returns an Err immediately, demonstrating how managed I/O failures
## become ordinary Roc Try errors rather than exceptions through native frames.
main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), StderrErr(Str), StdinErr(Str)])
main! = |args| {
    Stdout.line!("args: ${Str.join_with(args, "|")}")?
    line = Stdin.line!({})?
    Stdout.line!("input: ${line}")?
    Stderr.line!("stderr: café 🚀")?
    Ok({})
}
