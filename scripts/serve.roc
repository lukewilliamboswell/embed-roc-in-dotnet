#!/usr/bin/env roc
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	roc: "nightly-2026-10-04-130536d",
}

import cli.Path
import cli.Stdout
import src/Script
import src/Server

## Serve one archive on an ephemeral loopback port, printing its complete URL.
main! = |args| {
	archive = Script.archive_arg(args)?
	Script.require_file!(archive)?
	name = Path.filename(archive)?.display()
	bytes = Path.read_bytes!(archive)?
	listener = Server.listen!()?
	Stdout.line!("http://127.0.0.1:${listener.local_port!()?.to_str()}/${name}")?
	Server.forever!(listener, name, bytes)
}
