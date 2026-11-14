# Commands

`gdpackage ...` commands are ran in the editor console.
[Headless entry points](#headless-entry-points) below run from a system shell.

`<package>` means an addon-relative path, a `res://` path, or an absolute filesystem
path inside the project. See [Package targets](setup.md#package-targets) for examples
and autocomplete behavior.

## Create and initialize

```text
gdpackage new_plugin <plugin_name>
gdpackage init package [--name=package|plugin|addon|version] <folder>
gdpackage init plugin <package>
gdpackage init license <--type> <package> <name> <year>
```

- `new_plugin` creates an empty editor plugin under `addons/` and initializes export settings.
- `init package` creates a library package, its own Git repository if needed, `src/`,
  and export settings. `--name` selects the cfg filename; default `package`, with
  `addon` and `version` are deprecated but work for legacy use.
- `init plugin` initializes export settings for an existing folder (creates export.yml).
- `init license` writes a `LICENSE`. Choose one of `--mit`, `--apache-2`,
  `--gpl-3`, `--bsd-3`, or `--isc`. Quote names containing spaces.

```text
gdpackage init license --mit my_plugin "Example Author" 2026
```

See [Setup](setup.md) for configuration locations and generated files.

## Preview and export

```text
gdpackage open gui <package>
gdpackage open export_dir <package>
```

- `open gui` opens the export GUI with the package selected.
- `open export_dir` opens its output folder.

```text
gdpackage export [--verbose] [--release [--local] [--refresh]] <package>
```

- `export` packages the current working tree.
- `--verbose` includes progress messages alongside warnings, errors, and the result.
- `--release` builds from tags and verifies the exported variants.
- With `--release`, `--local` fetches dependency tags from matching local checkouts;
  `--refresh` rechecks cached tags against remotes and fails if a tag moved.

See [Releases](releases.md) for prerequisites, dependency resolution, and toolchains.

## Requirements

```text
gdpackage require check [--tags] [--all] [--verbose] <package>
gdpackage require update [--overwrite] [--prune] [--export-config] <package>
gdpackage require consumers <owner/repo>
```

`require check` crawls export references and lists the target's requirements as
`owner/repo@tag`, one per line. Its flags select additional reporting:

- `--all`: show the full crawl grouped by the package that should declare each requirement.
- `--verbose`: include source references for the plain list or `--all` report.
- `--tags`: validate declared build, compile, and test requirements at their tags
  and check their resolved graph. Understated requirements warn; invalid graphs fail.

`require update` writes the discovered requirements into the target's cfg `require=`.
Existing pins are kept unless flags change that behavior:

- `--overwrite`: repin existing entries using the dependency's current cfg version.
- `--prune`: remove requirements the crawl no longer finds.
- `--export-config`: write an explicit `build_require` list in the export config instead.

`require consumers` lists packages under `res://addons/` that declare the given
repository in their cfg or build/compile/test requirements. It takes a repository
identifier, such as `brohd11/godot-yaml-parser`, rather than a package path.

See [Requirement maintenance](releases.md#requirement-maintenance) for pinning details.

## Tests and CI workflows

```text
gdpackage ci run_test [--verbose] [--local] [--refresh] <package>
gdpackage ci test_workflow [--allow-project-root] <package>
gdpackage ci release_workflow [--allow-project-root] <package>
```

- `run_test` tests the working tree against tagged requirements in an isolated project.
  `--verbose` shows progress and passing suites; failures and skips always appear.
  `--local` reads tagged dependencies from matching local checkouts; `--refresh`
  rechecks cached tags against remotes.
- `test_workflow` writes `.github/workflows/test.yml` for pushes and pull requests.
- `release_workflow` writes `.github/workflows/release.yml` for version tags.
- Workflow generators preserve existing files. For a package below its repository
  root, `--allow-project-root` writes there and sets `package-dir` to the package folder.

See [Testing](testing.md) and [Release CI](releases.md#release-ci) for setup.

## Compatibility inspection

```text
gdpackage min_version [--min=4.4] [--verbose] [--full] <package>
```

Scans exported files for version-gated syntax and API usage and reports the minimum
Godot version. `--verbose` includes every occurrence with its file and line.
`--min=VER` filters displayed findings to those introduced above that version; it
does not change the scan or reported minimum. The console variable
`$GDPACKAGE_MIN_VERSION` supplies a persistent filter; the flag takes precedence.
`--full` is reserved for a deeper scan and currently runs the standard scan.

For maintainer use, `gdpackage min_version generate_api` rebuilds the API index from
the extension API dumps in GDPackage's export-ignore folder.
See [Backporting](optimization.md#backport) for export transformations.

## Headless entry points

From a system shell, with GDPackage installed in the project:

```sh
godot --headless --path /path/to/project --script res://addons/gdpackage/src/class/release/test_cli.gd -- addons/my_plugin
godot --headless --path /path/to/project --script res://addons/gdpackage/src/class/release/release_cli.gd -- addons/my_plugin
```

Both take a project-relative package path, a `res://` path, or an absolute path inside
the project, followed by optional `--tree <checkout>`, `--refresh`, and `--local`.
`--tree` selects a separate source checkout when it lives elsewhere than the install path.
Unlike console targets, project-relative shell targets include `addons/`.

The test entry exits `0` on success or `1` on failure and prints a `PE_TEST_OUTPUT`
JSON report. The release entry exits `0` on success or `1` on failure and prints
exported zip paths as `PE_RELEASE_OUTPUT` JSON. Invalid arguments exit `2`.
Use [Testing](testing.md#gdpackage-development-checks) for GDPackage's own suite runner.
