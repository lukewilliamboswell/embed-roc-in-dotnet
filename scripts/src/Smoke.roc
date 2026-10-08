import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.Tcp
import cli.Url
import Script
import Server

## Consume a packaged platform through HTTP, then exercise the managed API and CLI.
Smoke := [].{

	## Compare a real HTTP response with the exact archive bytes passed by CI.
	## This runs in a child while the smoke driver services the loopback listener.
	fetch! : Str, Path => Try({}, _)
	fetch! = |url, archive| {
		parsed = Url.parse(url)?
		port = match parsed.port() {
			Some(value) => value
			None => return Err(ExpectedExplicitLoopbackPort)
		}
		stream = Tcp.connect!(parsed.host(), port, 5_000)?
		stream.write_utf8!("GET ${parsed.path()} HTTP/1.1\r\nHost: ${parsed.host()}\r\nConnection: close\r\n\r\n", 5_000)?
		status = stream.read_line!(65_536, 5_000)?
		consume_headers!(stream, 0)?
		expected = Path.read_bytes!(archive)?
		body = stream.read_exactly!(expected.len(), 30_000)?
		trailing = stream.read_up_to!(1, 5_000)?
		if status != "HTTP/1.1 200 OK\r\n" or body != expected or !trailing.is_empty() {
			Err(HttpArtifactMismatch)
		} else {
			Ok({})
		}
	}

	## Build isolated URL-based app copies against one prebuilt platform artifact.
	## Every compiler child receives fresh Roc and XDG caches; no local adapter
	## source or previously downloaded platform can satisfy the application build.
	run! : Path, Path => Try({}, _)
	run! = |root, archive| {
		Script.require_file!(archive)?
		# Build once before capturing the CLI so SDK/build messages cannot become
		# application output on the first .NET invocation in a fresh CI checkout.
		Script.run!(Cmd.new("dotnet").env("DOTNET_NOLOGO", "1").args(["build", Path.to_os_str(Path.join(root, "RocEmbedding.slnx")), "--nologo"]))?
		bytes = Path.read_bytes!(archive)?
		name = Path.filename(archive)?.display()
		Env.with_temp_dir!(
			|work| {
				listener = Server.listen!()?
				port = listener.local_port!()?
				url = "http://127.0.0.1:${port.to_str()}/${name}"
				Stdout.line!("SERVE ${url}")?
				# Close the listener deterministically on both success and test failure.
				result = consume!(root, work, archive, url, listener, name, bytes)
				_ = listener.close!()
				result
			},
		)?
		Stdout.line!("Bundle HTTP fetch and managed smoke passed")
	}
}

## Skip the bounded header section before comparing the exact binary body.
consume_headers! = |stream, count| {
	if count >= 100 {
		return Err(TooManyHttpHeaders)
	}
	line = stream.read_line!(65_536, 5_000)?
	if line == "\r\n" {
		Ok({})
	} else {
		consume_headers!(stream, count + 1)
	}
}

## Service a fetch probe first, proving that the exact named artifact is served.
consume! = |root, work, archive, url, listener, name, bytes| {
	probe = Script.roc!()?.args([
		Path.to_os_str(Path.join(root, "scripts/smoke.roc")),
		"--",
		"--fetch",
		OsStr.from_str(url),
		Path.to_os_str(archive),
	]).cwd(root).stdout(Capture).stderr(Capture).timeout_ms(180_000).manage_tree(Bool.True).spawn!()
		.map_err(|err| FetchProbeSpawnFailed(err))?
	Script.success!(Server.wait!(probe, listener, name, bytes)?)?
	for example in ["hello_world", "effects", "exit"] {
		application = Path.join(work, example)
		Path.create_all!(application)?
		source = Path.read_utf8!(Path.join(root, "examples/${example}/main.roc"))?
		declaration = "platform \"../../platform/main.roc\""
		if source.split_on(declaration).len() != 2 {
			return Err(ExpectedOnePlatformDeclaration(example))
		}
		Path.write_utf8!(Path.join(application, "main.roc"), source.replace_each(declaration, "platform \"${url}\""))?
		filename = match Env.platform!().os {
			LINUX => "app.so"
			WINDOWS => "app.dll"
			_ => return Err(UnsupportedSmokeOperatingSystem)
		}
		library = Path.join(application, filename)
		# Compilation caching and dependency caching are separate; isolate both.
		build = Script.roc!()?.args([
			"build",
			Path.to_os_str(Path.join(application, "main.roc")),
			OsStr.from_str("--output=${Path.display(library)}"),
			"--no-cache",
		]).cwd(application)
			.env("ROC_CACHE_DIR", Path.to_os_str(Path.join(application, "roc-cache")))
			.env("XDG_CACHE_HOME", Path.to_os_str(Path.join(application, "xdg-cache")))
			.stdout(Capture).stderr(Capture).timeout_ms(180_000).manage_tree(Bool.True)
		child = build.spawn!().map_err(|err| ApplicationBuildSpawnFailed(err))?
		Script.success!(Server.wait!(child, listener, name, bytes)?)?
		Script.require_file!(library)?
		check_cli!(root, example, library)?
		if example == "effects" {
			# The separate executable tests RocPlugin through its public .NET API,
			# including managed failures, reentrancy, concurrency, and disposal.
			Script.run!(
				Cmd.new("dotnet").args([
					"run",
					"--project",
					Path.to_os_str(Path.join(root, "dotnet-tests")),
					"--",
					Path.to_os_str(library),
				]),
			)?
		}
		Stdout.line!("PASS ${example}")?
	}
	Ok({})
}

## Run the documented console command with redirected UTF-8 stdin/out/err.
## Normalize only Windows line endings; text, arguments, and statuses stay exact.
check_cli! : Path, Str, Path => Try({}, _)
check_cli! = |root, example, library| {
	base = Cmd.new("dotnet").env("DOTNET_NOLOGO", "1").args([
		"run",
		"--project",
		Path.to_os_str(Path.join(root, "dotnet-host")),
		"--",
		Path.to_os_str(library),
	])
	output = if example == "effects" {
		Script.capture!(base.args(["α", "β"]), "héllo 🚀\n")?
	} else {
		Script.capture!(base, "")?
	}
	stdout = Str.from_utf8(output.stdout_bytes)?.replace_each("\r\n", "\n")
	stderr = Str.from_utf8(output.stderr_bytes)?.replace_each("\r\n", "\n")
	expected_status = if example == "exit" Exited(42) else Exited(0)
	if output.status != expected_status {
		return Err(UnexpectedCliExit(example, output.status, stdout, stderr))
	}
	match example {
		"hello_world" =>
			if stdout == "Hello, World!\n" and stderr == "" Ok({}) else Err(HelloWorldOutputMismatch(stdout, stderr))
		"effects" =>
			if stdout.contains("args: α|β\n") and stdout.contains("input: héllo 🚀\n") and stderr.contains("stderr: café 🚀\n") {
				Ok({})
			} else {
				Err(ManagedConsoleOutputMismatch(stdout, stderr))
			}
		"exit" => Ok({})
		_ => Err(UnknownExample(example))
	}
}
