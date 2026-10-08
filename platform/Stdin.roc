import Host

## Effectful functions for reading from this invocation's managed standard input.
Stdin := [].{
    ## Read one line from standard input.
    ##
    ## The returned string does not include the trailing newline. On EOF this returns
    ## an empty string.
    ##
    ## This API therefore cannot distinguish EOF from an empty line. The caller's
    ## TextReader supplies the line; Unicode and long lines are copied into Roc Str values.
    ## The empty record argument `{}` denotes an operation with no input data.
    ##
    ## Returns `Err(StdinErr(message))` if the host cannot read from stdin.
    line! : {} => Try(Str, [StdinErr(Str)])
    line! = |{}|
        match Host.stdin_line!({}) {
            Ok(line) => Ok(line)
            Err(StdinErr(err)) => Err(StdinErr(err))
        }
}
