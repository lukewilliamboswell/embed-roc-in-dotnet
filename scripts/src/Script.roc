import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout

## Shared process and path helpers for the repository's Roc automation.
Script := [].{

	## Use the same pinned compiler for scripts, generated glue, and applications.
	## ROC_NIGHTLY may name an absolute executable path in a development shell.
	roc! = ||
		match Env.var!("ROC_NIGHTLY") {
			Ok(program) => Ok(Cmd.new(program))
			Err(VarNotFound(_)) => Ok(Cmd.new("roc"))
			Err(err) => Err(CompilerEnvironmentError(err))
		}

	## Run from the repository root, where the public script commands are invoked.
	root! = || {
		root = Env.cwd!()?
		if Path.is_file!(Path.join(root, "platform/main.roc"))? {
			Ok(root)
		} else {
			Err(RunFromRepositoryRoot)
		}
	}

	## Print a command and inherit console streams for interactive build output.
	run! = |command| {
		Stdout.line!("RUN ${Cmd.to_str(command)}")?
		command.timeout_ms(180_000).manage_tree(Bool.True).exec_cmd!()
	}

	## Capture redirected streams and preserve nonzero exit codes as test data.
	capture! = |command, input|
		command.stdin(Bytes(Str.to_utf8(input))).timeout_ms(180_000).manage_tree(Bool.True).run!()
			.map_err(|err| ProcessFailed(err))

	## Report captured diagnostics and require a successful child exit.
	success! = |output| {
		match output.status {
			Exited(0) => Ok({})
			Exited(code) => {
				Stderr.write_bytes!(output.stderr_bytes)?
				Stderr.write_bytes!(output.stdout_bytes)?
				Err(CommandExited(code))
			}
			Signaled(signal) => Err(CommandSignaled(signal))
		}
	}

	## Require a regular file and reject symlinks in the packaged inventory.
	require_file! = |path| {
		if Path.is_file!(path)? and !Path.is_sym_link!(path)? {
			Ok({})
		} else {
			Err(MissingFile(Path.display(path)))
		}
	}

	## Accept one path argument without assuming the operating system's encoding.
	archive_arg = |args|
		match args {
			[archive] => Ok(Path.from_raw(OsStr.to_raw(archive)))
			_ => Err(ExpectedOneArchiveArgument)
		}
}
