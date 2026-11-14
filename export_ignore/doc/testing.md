# Testing

## Native suite setup

Name native suites `*_test.gd` and expose a static `run`, `run_test`, or `run_tests`
entry point returning a dictionary. `result` is an integer failure count (`0` passes),
and `output` is an array of report lines:

```gdscript
static func run_tests() -> Dictionary:
	var failures := 0
	var output: Array = []
	# Run checks, increment failures, and append report lines here.
	return {"result": failures, "output": output}
```

The runner also accepts instance entry methods and legacy `success` booleans.
Suites can await frames. A script that cannot load or returns a non-dictionary fails;
files without an entry point are reported as invalid. Native CI fails when no suites run.

Keep suites, fixtures, and runners in the package's `_export_ignore/test/` or
`export_ignore/test/` folder for a development-only layout. Adjacent suites are also
supported; use the exclusion rules below to keep fixtures out of releases.

## Test CI

`gdpackage ci run_test <package>` tests the working tree in an isolated project against its
declared dependencies at their tags. The package needs a Git `origin` to identify it,
but its working tree does not need a release tag. `test_require` in the export YAML
adds test-only dependencies; they are excluded from release dependency resolution.
An omitted `test_require` uses the package cfg's `require` list. Use `"@require"`
alongside extra test dependencies to retain that list, or `[]` to declare none.
See [Releases](releases.md#build-requirements) for the build and compile requirements.

```text
gdpackage ci run_test --verbose my_plugin
gdpackage ci run_test --local my_plugin
gdpackage ci run_test --refresh my_plugin
```

`--local` fetches dependency tags from matching checkouts in the project; dependencies
still use committed, tagged files. `--refresh` rechecks cached tags against remotes.

By default CI discovers adjacent `*_test.gd` suites throughout the package, plus the canonical
`_export_ignore/test` or `export_ignore/test` directory. Hidden and `.gdignore` directories are
skipped, and framework suites are left to their own runners. Native suites expose
`run`, `run_test`, or `run_tests`. Packages
using another Godot CLI runner can instead configure commands in their export YAML.

## GUT, GDUnit4, and custom runners

For example, configure framework dependencies and their CLI scripts:

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

Commands replace native suite discovery. GDPackage imports dependencies, then runs every command
with the current Godot executable and `--headless --path <workspace> --script <script>`. `args` is
an argument array passed unchanged, without a shell or an implicit `--`. Scripts using
`OS.get_cmdline_user_args()` should include `--` themselves. `name` defaults to the script path;
`timeout` defaults to 600 seconds per command. Empty command lists are errors.
`script` must be a `res://` path inside the workspace, `args` must contain strings,
and an explicit `timeout` must be a positive number of seconds.

Only exit zero passes. Failures include the command output and exit status; remaining commands
still run. The CLI's JSON report represents each command as a suite. Frameworks own test discovery
and assertion handling: a command that finds no tests may still return zero. Check framework
reports when proving coverage. GUT's `.gutconfig.json` and GDUnit's saved runner configuration are
optional when directories and options are passed explicitly. GDUnit4 6.2.3 requires
`--ignoreHeadlessMode` for non-UI tests; UI input tests need a display and are outside this runner.

The temporary project supplies no game autoloads or input mappings, and does not enable framework
editor plugins. Tests must be self-contained.

## GitHub Actions

Generate a caller workflow from the editor console:

```text
gdpackage ci test_workflow my_plugin
```

This writes `.github/workflows/test.yml` at the package repository root, running on
branch pushes, pull requests, and manual dispatch. Existing workflow files are preserved.
If the package is below its repository root, pass `--allow-project-root`; the generator
sets `package-dir` so only that package is tested.

The generated workflow selects the running editor's Godot build. Edit `godot-versions`
to provide a JSON array of builds for a matrix. The reusable workflow follows its
selected Git ref, but downloads a released GDPackage toolchain; pin `toolchain-version`
when adopting new runner features. `install-path` and `package-dir` can override
package layout detection. See [Commands](commands.md#headless-entry-points) for the
headless entry used by CI.

## Excluding tests from exports

Tests can live beside the code they exercise. Export options default to `ignore_tests: true`,
which omits `*_test.gd` and GUT/GDUnit4-derived scripts from initial file selection. Detection
follows custom test bases without loading the framework. Tests stay in source checkouts and CI
workspaces. A retained file's required dependency or an explicit `other_transfers` entry can
still bring a test into the release; its dependencies are gathered normally. Set
`options.ignore_tests: false` to keep tests in ordinary export selection. Test scenes and fixture
data still need ordinary export exclusions.

## GDPackage development checks

From this development project's root, run GDPackage's own suites and optimizer smoke test:

```sh
godot --headless --path . --script res://addons/gdpackage/export_ignore/test/run_headless.gd
python3 addons/gdpackage/export_ignore/test/optimizer_export_smoke.py --godot /path/to/godot
```

The smoke test exports the fixture plugin with optimizer and packaging variants,
executes their struct and inline workloads in isolated projects, and compares results.
These commands require the development checkout and its test fixtures; the release
package excludes them.
