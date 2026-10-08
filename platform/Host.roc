## Internal hosted-effect boundary used by the platform wrappers.
##
## Applications should import `Stdout`, `Stderr`, and `Stdin` instead.
## These declarations have no Roc bodies: the platform's `hosted` section binds
## each one to a Zig symbol which dispatches to the current managed host.
Host := [].{
	## Write a line through the caller's managed error writer.
	stderr_line! : Str => Try({}, [StderrErr(Str)])
	## Read a line through the caller's managed reader; EOF is successful empty input.
	stdin_line! : {} => Try(Str, [StdinErr(Str)])
	## Write a line through the caller's managed output writer.
	stdout_line! : Str => Try({}, [StdoutErr(Str)])
}
