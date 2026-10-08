import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import Script

## Package the platform's explicit consumer inventory with Roc's content hash.
Bundle := [].{

	## These paths are relative to platform/, and become archive paths verbatim.
	files : List(Str)
	files = [
		"main.roc",
		"Host.roc",
		"Stdout.roc",
		"Stderr.roc",
		"Stdin.roc",
		"targets/x64musl/libhost.a",
		"targets/x64win/host.lib",
	]

	## Stage only declared modules, both native archives, and the platform license.
	## Return the original Roc-generated archive path; its filename is part of URLs.
	build! : Path, Path => Try(Path, _)
	build! = |root, output_directory| {
		output = Path.absolute!(output_directory)?
		Path.create_all!(output)?
		Env.with_temp_dir!(
			|stage| {
				for relative in files {
					source = Path.join(Path.join(root, "platform"), relative)
					Script.require_file!(source)?
					destination = Path.join(stage, relative)
					# All archive parents are known, so staging creates no implicit inputs.
					Path.create_all!(Path.join(stage, "targets/x64musl"))?
					Path.create_all!(Path.join(stage, "targets/x64win"))?
					Path.copy!(source, destination)?
				}
				Path.create_all!(Path.join(stage, "licenses"))?
				Path.copy!(Path.join(root, "LICENSE"), Path.join(stage, "licenses/platform.txt"))?
				command = Script.roc!()?.args_str(["bundle"].concat(files).concat(["licenses/platform.txt", "--output-dir", Path.display(output)]))
				result = Script.capture!(command.cwd(stage), "")?
				Script.success!(result)?
				Stdout.write_bytes!(result.stdout_bytes)?
				# Do not guess a filename or select a possibly stale archive in output/.
				reported = Str.from_utf8(result.stdout_bytes.concat(result.stderr_bytes))?
				created = reported.split_on("\n").keep_if(|line| line.starts_with("Created:"))
				archive = match created {
					[line] => Path.utf8(line.replace_each("Created:", "").trim())
					_ => return Err(ExpectedOneCreatedArchive)
				}
				Script.require_file!(archive)?
				# Use Roc's own portable extraction to inspect the packaged inventory.
				validation = Path.join(stage, "validation")
				Path.create_all!(validation)?
				extracted = Script.capture!(Script.roc!()?.args(["unbundle", Path.to_os_str(archive)]).cwd(validation), "")?
				Script.success!(extracted)?
				for native in ["targets/x64musl/libhost.a", "targets/x64win/host.lib"] {
					# roc unbundle places the inventory under the archive's content hash.
					if !contains_native!(validation, native)? {
						return Err(BundleMissingNativeArchive(native))
					}
				}
				Ok(archive)
			},
		)
	}
}

## Find a declared native input after Roc extracts the bundle into its hash folder.
contains_native! : Path, Str => Try(Bool, _)
contains_native! = |directory, relative| {
	if Path.is_file!(Path.join(directory, relative))? {
		return Ok(Bool.True)
	}
	for entry in Path.list!(directory)? {
		if Path.is_dir!(entry)? and Path.is_file!(Path.join(entry, relative))? {
			return Ok(Bool.True)
		}
	}
	Ok(Bool.False)
}
