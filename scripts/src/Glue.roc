import cli.Path
import Script

## Generate the Zig ABI declarations from platform/main.roc with the pinned spec.
Glue := [].{

	## Verify the compiler matches the vendored specification's release provenance.
	verify_compiler! = || {
		result = Script.capture!(Script.roc!()?.arg("version"), "")?
		Script.success!(result)?
		if Str.from_utf8(result.stdout_bytes)?.contains("nightly-2026-10-04-130536d") {
			Ok({})
		} else {
			Err(RequiresPinnedCompiler("nightly-2026-10-04-130536d"))
		}
	}

	## Write raw generator output into the chosen directory without postprocessing.
	## Roc's compiler-owned `platform glue` supplies layouts and ownership policies.
	generate! : Path, Path => Try({}, _)
	generate! = |root, output| {
		verify_compiler!()?
		Script.run!(
			Script.roc!()?.args([
				"glue",
				"--no-cache",
				Path.to_os_str(Path.join(root, "scripts/glue/ZigGlue.roc")),
				Path.to_os_str(output),
				Path.to_os_str(Path.join(root, "platform/main.roc")),
			]),
		)
	}
}
