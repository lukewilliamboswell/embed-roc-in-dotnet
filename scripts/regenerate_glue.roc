#!/usr/bin/env roc
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	roc: "nightly-2026-10-04-130536d",
}

import cli.Path
import src/Glue
import src/Script

## Regenerate the checked-in Zig ABI declarations after editing the Roc platform.
main! = |_args| {
	root = Script.root!()?
	Glue.generate!(root, Path.join(root, "host-shim"))
}
