# Commands

`gdpackage ...` commands are run in the editor console. [Headless entry points](#headless-entry-points) run from a system shell.

`<package>` is an addon-relative path, a `res://` path, or an absolute filesystem path inside the project. See [Package targets](setup.md#package-targets).

## Create and initialize

```text
gdpackage new_plugin <plugin_name>
gdpackage init package [--name=package|plugin|addon|version] <folder>
gdpackage init plugin <package>
gdpackage init license <--type> <package> <name> <year>
```

- `new_plugin` creates an empty editor plugin under `addons/` with export settings.
- `init package` creates a library package: its own Git repository if needed, `src/`, and export settings. `--name` picks the cfg filename, default `package`. `addon` and `version` are deprecated.
- `init plugin` creates `export.yml` for an existing folder.
- `init license` writes a `LICENSE`. Type is one of `--mit`, `--apache-2`, `--gpl-3`, `--bsd-3`, `--isc`. Quote names containing spaces.

```text
gdpackage init license --mit my_plugin "Example Author" 2026
```

See [Setup](setup.md) for the generated files.

## Preview and export

```text
gdpackage open gui <package>
gdpackage open export_dir <package>
gdpackage export [--verbose] [--release [--local] [--refresh]] <package>
```

- `open gui` opens the export GUI with the package selected.
- `open export_dir` opens its output folder.
- `export` packages the current working tree.
- `--verbose` adds progress messages to the warnings, errors and result.
- `--release` builds from tags and verifies the exported variants. See [Releases](releases.md).
- `--local` (with `--release`) takes dependency tags from matching local checkouts.
- `--refresh` (with `--release`) rechecks cached tags against their remotes and fails if one moved.

## Requirements

```text
gdpackage require check [--tags] [--all] [--verbose] <package>
gdpackage require update [--overwrite] [--prune] [--export-config] <package>
gdpackage require consumers <owner/repo>
```

`require check` crawls export references and lists the package's requirements as `owner/repo@tag`, one per line.

- `--all` shows the full crawl, grouped by the package that should declare each requirement.
- `--verbose` adds source references to the plain list or the `--all` report.
- `--tags` validates declared build, compile and test requirements at their tags and checks the resolved graph. Understated requirements warn; invalid graphs fail.

`require update` writes the discovered requirements into the package's cfg `require=`. Existing pins are kept.

- `--overwrite` re-pins existing entries to the dependency's current cfg version.
- `--prune` removes requirements the crawl no longer finds.
- `--export-config` writes an explicit `build_require` list in the export config instead.

`require consumers` lists packages under `res://addons/` that declare the given repository in their cfg or build/compile/test requirements. It takes a repository identifier such as `brohd11/godot-yaml-parser`, not a package path.

See [Requirement maintenance](releases.md#requirement-maintenance) for pinning details.

## Tests and CI workflows

```text
gdpackage ci run_test [--verbose] [--local] [--refresh] <package>
gdpackage ci test_workflow [--allow-project-root] <package>
gdpackage ci release_workflow [--allow-project-root] <package>
```

- `run_test` tests the working tree against tagged requirements in an isolated project.
  - `--verbose` shows progress and passing suites. Failures and skips always show.
  - `--local` and `--refresh` work as they do for `export --release`.
- `test_workflow` writes `.github/workflows/test.yml`, run on pushes and pull requests.
- `release_workflow` writes `.github/workflows/release.yml`, run on version tags.
- Neither generator overwrites an existing file. For a package below its repository root, `--allow-project-root` writes at the root and sets `package-dir` to the package folder.

See [Testing](testing.md) and [Release CI](releases.md#release-ci).

## Compatibility inspection

```text
gdpackage min_version [--min=4.4] [--verbose] [--full] <package>
```

Scans exported files for version-gated syntax and API usage, and reports the minimum Godot version.

- `--verbose` lists every occurrence with its file and line.
- `--min=VER` only shows findings introduced above that version. The scan and the reported minimum are unchanged. The console variable `$GDPACKAGE_MIN_VERSION` sets a persistent filter; the flag takes precedence.
- `--full` is reserved for a deeper scan and currently runs the standard one.

`gdpackage min_version generate_api` rebuilds the API index from the extension API dumps in GDPackage's export-ignore folder (maintainer use).

## Headless entry points

From a system shell, with GDPackage installed in the project:

```sh
godot --headless --path /path/to/project --script res://addons/gdpackage/src/class/release/test_cli.gd -- addons/my_plugin
godot --headless --path /path/to/project --script res://addons/gdpackage/src/class/release/release_cli.gd -- addons/my_plugin
```

- The target is a project-relative path, a `res://` path, or an absolute path inside the project. Unlike console targets, project-relative paths include `addons/`.
- Optional flags follow: `--tree <checkout>`, `--refresh`, `--local`. `--tree` points at a source checkout that lives somewhere other than the install path.
- Exit codes: `0` success, `1` failure, `2` invalid arguments.
- The test entry prints a `PE_TEST_OUTPUT` JSON report. The release entry prints the exported zip paths as `PE_RELEASE_OUTPUT` JSON.

GDPackage's own suite runner is under [Testing](testing.md#gdpackage-development-checks).
