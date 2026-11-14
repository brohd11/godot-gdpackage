# Testing

## Native suite setup

A native suite is a `*_test.gd` file with a static `run`, `run_test`, or `run_tests` entry point returning a dictionary. `result` is the failure count (`0` passes) and `output` is an array of report lines:

```gdscript
static func run_tests() -> Dictionary:
	var failures := 0
	var output: Array = []
	# Run checks, increment failures, and append report lines here.
	return {"result": failures, "output": output}
```

- Instance entry methods and a `success` bool in place of `result` are also accepted.
- Suites can await frames.
- A script that cannot load, or returns a non-dictionary, fails. Files without an entry point are reported as invalid.
- CI fails when no suites run.

Keep suites, fixtures, and runners in the package's `_export_ignore/test/` (or `export_ignore/test/`) folder and they never reach a release. Suites beside the code they test also work, see [Excluding tests from exports](#excluding-tests-from-exports).

## Test CI

`gdpackage ci run_test <package>` tests the working tree in an isolated project, against its declared dependencies at their tags.

```text
gdpackage ci run_test --verbose my_plugin
gdpackage ci run_test --local my_plugin
gdpackage ci run_test --refresh my_plugin
```

- The package needs a Git `origin` to identify it. Its working tree does not need a release tag.
- `--local` takes dependency tags from matching checkouts in the project. Only committed, tagged files are used.
- `--refresh` rechecks cached tags against their remotes.
- `test_require` in `export.yml` lists the test dependencies. Omitted, it uses the package cfg's `require=` list. Include `"@require"` to keep that list alongside extra entries, or use `[]` for none. Test requirements are left out of release resolution. See [Build requirements](releases.md#build-requirements) for the other keys.
- Suites are discovered throughout the package, plus the export-ignore `test` folder. Hidden and `.gdignore` directories are skipped, and framework suites are left to their own runners.
- The temporary project has no game autoloads or input mappings, and enables no framework editor plugins. Tests must be self-contained.

## GUT, GDUnit4, and custom runners

A package using another Godot CLI runner sets commands in `export.yml`. Commands replace native suite discovery.

```yaml
test_require:
  - "@require"
  - "bitwes/Gut@v9.7.1"
  - "godot-gdunit-labs/gdUnit4@v6.2.3"
test:
  commands:
    - name: gut
      script: res://addons/gut/gut_cmdln.gd
      args: ["-gdir=res://addons/my_plugin/_export_ignore/test/gut", "-ginclude_subdirs", "-gexit"]
    - name: gdunit4
      script: res://addons/gdUnit4/bin/GdUnitCmdTool.gd
      args: ["-a", "res://addons/my_plugin/_export_ignore/test/gdunit4", "--ignoreHeadlessMode"]
      timeout: 600
```

Dependencies are imported, then each command runs with the current Godot executable as `--headless --path <workspace> --script <script>` followed by its `args`.

- `script` - a `res://` path inside the workspace.
- `args` - array of strings, passed unchanged with no shell and no implicit `--`. Scripts using `OS.get_cmdline_user_args()` need `--` in the list.
- `name` - defaults to the script path.
- `timeout` - positive number of seconds, default 600.
- An empty `commands` list is an error.

Results:

- Only exit code zero passes. A failure includes the command output and exit status, and the remaining commands still run.
- Each command is one suite in the JSON report.
- The framework owns test discovery and assertions. A command that finds no tests may still exit zero, so check the framework's own report.
- GUT's `.gutconfig.json` and GDUnit's saved runner configuration are optional when directories and options are passed explicitly.
- GDUnit4 6.2.3 requires `--ignoreHeadlessMode` for non-UI tests. UI input tests need a display and are not supported.

## GitHub Actions

Generate a caller workflow from the editor console:

```text
gdpackage ci test_workflow my_plugin
```

- Writes `.github/workflows/test.yml` at the package repository root, running on branch pushes, pull requests, and manual dispatch. An existing file is not overwritten.
- For a package below its repository root, pass `--allow-project-root`. `package-dir` is set so only that package is tested.
- `godot-versions` is set to the running editor's Godot build. Edit it to a JSON array of builds for a matrix.
- The reusable workflow follows its selected Git ref, but downloads a released GDPackage toolchain. Pin `toolchain-version` when adopting new runner features.
- `install-path` and `package-dir` override package layout detection.
- For dependencies in private repositories, pass a `deps-token` secret. See [Private dependencies](releases.md#private-dependencies).

CI uses the [headless entry point](commands.md#headless-entry-points).

## Excluding tests from exports

`options.ignore_tests` defaults to true, so tests can live beside the code they exercise.

- `*_test.gd` files and GUT/GDUnit4-derived scripts are left out of the initial file selection. Custom test bases are followed, without loading the framework.
- A test can still be exported when a kept file depends on it, or through an explicit `other_transfers` entry. Its dependencies are gathered normally.
- Test scenes and fixture data need ordinary export exclusions.
- Set `ignore_tests: false` to treat tests like any other file.

## GDPackage development checks

From this development project's root, run GDPackage's own suites and the optimizer smoke test:

```sh
godot --headless --path . --script res://addons/gdpackage/export_ignore/test/run_headless.gd
python3 addons/gdpackage/export_ignore/test/optimizer_export_smoke.py --godot /path/to/godot
```

The smoke test exports the fixture plugin with optimizer and packaging variants, runs their struct and inline workloads in isolated projects, and compares results. Both need the development checkout and its fixtures, which the release package excludes.
