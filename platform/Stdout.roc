import Host

## Effectful functions for writing to this invocation's managed standard output.
## The empty tag union makes Stdout a namespace; it has no values to construct.
Stdout := [].{
    ## Write the given string to standard output, followed by a newline.
    ##
    ## The embedding application supplies the writer and its newline policy.
    ## Empty strings and Unicode are supported, without a fixed buffer limit.
    ## Returns `Err(StdoutErr(message))` if the host cannot write to stdout.
    line! : Str => Try({}, [StdoutErr(Str)])
    line! = |message|
        match Host.stdout_line!(message) {
            Ok({}) => Ok({})
            Err(StdoutErr(err)) => Err(StdoutErr(err))
        }
}
