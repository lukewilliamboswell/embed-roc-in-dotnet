#!/usr/bin/env roc
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	roc: "nightly-2026-10-04-130536d",
}

import cli.Cmd
import cli.Env
import cli.Path
import cli.OsStr
import cli.Stdout
import src/Bundle
import src/Glue
import src/Script
import src/Smoke

## Regenerate ABI glue in isolation, compile both adapters from it, and test .NET.
## Comparing first detects stale checked-in glue; the isolated build then proves
## the current generator output itself can complete the full consumer workflow.
main! = |args| {
	root = Script.root!()?
	mode = match args.map(OsStr.display) {
		[] => Full
		["--package-only", output] => PackageOnly(Path.utf8(output))
		_ => return Err(Usage("roc scripts/check_all.roc [-- --package-only <output-directory>]"))
	}
	Env.with_temp_dir!(
		|work| {
			# Only native build inputs are copied. Generated archives and Zig caches
			# are deliberately excluded, so both target adapters must be rebuilt.
			for file in ["build.zig", "build.zig.zon", "LICENSE"] {
				Path.copy!(Path.join(root, file), Path.join(work, file))?
			}
			Path.copy_dir!(Path.join(root, "platform"), Path.join(work, "platform"))?
			if Path.is_dir!(Path.join(work, "platform/targets"))? {
				Path.delete_all!(Path.join(work, "platform/targets"))?
			}
			Path.create_all!(Path.join(work, "host-shim"))?
			Path.copy!(Path.join(root, "host-shim/host.zig"), Path.join(work, "host-shim/host.zig"))?
			Glue.generate!(root, Path.join(work, "host-shim"))?
			generated = Path.join(work, "host-shim/roc_platform_abi.zig")
			if Path.read_bytes!(generated)? != Path.read_bytes!(Path.join(root, "host-shim/roc_platform_abi.zig"))? {
				return Err(StaleAbiGlue("Run roc scripts/regenerate_glue.roc"))
			}
			Script.run!(Cmd.new("zig").args(["build", "-Doptimize=ReleaseSafe"]).cwd(work))?
			output = match mode {
				Full => root
				PackageOnly(directory) => directory
			}
			archive = Bundle.build!(work, output)?
			if mode == Full {
				Smoke.run!(root, archive)?
			}
			Stdout.line!("PASS regenerated glue compiles both ReleaseSafe adapters and packages successfully")
		},
	)
}
