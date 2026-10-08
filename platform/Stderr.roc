import Host

## Effectful functions for writing to this invocation's managed standard error.
## Roc runtime diagnostics also use this writer through the host adapter.
Stderr := [].{
    ## Write the given string to standard error, followed by a newline.
    ##
    ## The embedding application supplies the writer and its newline policy.
    ## Empty strings and Unicode are supported, without a fixed buffer limit.
    ## Returns `Err(StderrErr(message))` if the host cannot write to stderr.
    line! : Str => Try({}, [StderrErr(Str)])
    line! = |message|
        match Host.stderr_line!(message) {
            Ok({}) => Ok({})
            Err(StderrErr(err)) => Err(StderrErr(err))
        }
}
