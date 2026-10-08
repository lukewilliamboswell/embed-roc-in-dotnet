#!/usr/bin/env roc
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	roc: "nightly-2026-10-04-130536d",
}

import cli.Stdout
import src/Bundle
import src/Script

## Create a verified platform bundle in the repository root and print its path.
main! = |_args| {
	root = Script.root!()?
	archive = Bundle.build!(root, root)?
	Stdout.line!(archive.display())
}
