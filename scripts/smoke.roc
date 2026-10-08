#!/usr/bin/env roc
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	roc: "nightly-2026-10-04-130536d",
}

import cli.OsStr
import cli.Path
import src/Script
import src/Smoke

## Test one downloaded archive as an external Roc/.NET consumer on Linux or Windows.
main! = |args| {
	match args {
		[command, url, archive] => {
			if OsStr.display(command) != "--fetch" {
				return Err(ExpectedOneArchiveArgument)
			}
			Smoke.fetch!(OsStr.to_str_try(url)?, Path.from_raw(OsStr.to_raw(archive)))
		}
		_ => {
			root = Script.root!()?
			archive = Path.absolute!(Script.archive_arg(args)?)?
			Smoke.run!(root, archive)
		}
	}
}
