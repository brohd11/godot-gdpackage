extends SceneTree
## Headless test CI, the entry the test workflow runs:
##     godot --headless --path <project> --script res://addons/gdpackage/src/class/release/test_cli.gd -- <package dir> [--tree <checkout>] [--refresh] [--local]
## <package dir> is where the package installs; --tree is its checkout when that's elsewhere.
## Exits 0 when the package's suites pass against its requires at their tags, printing TestRunner's
## report as one OUTPUT_PREFIX line of JSON ({} if the suites never ran).

const TestCI = preload("res://addons/gdpackage/src/class/release/test_ci.gd")
const ReleaseCli = preload("res://addons/gdpackage/src/class/release/release_cli.gd")

const OUTPUT_PREFIX = "PE_TEST_OUTPUT "
const USAGE = "usage: test_cli.gd -- <package dir> [--tree <checkout>] [--refresh] [--local]"


func _init() -> void:
	var target = ""
	var tree = ""
	var refresh = false
	var local = false
	var args = OS.get_cmdline_user_args()
	var i = 0
	while i < args.size():
		var arg = args[i]
		i += 1
		match arg:
			"--refresh": refresh = true
			"--local": local = true
			"--tree":
				if i >= args.size():
					printerr(USAGE)
					quit(2)
					return
				tree = args[i].strip_edges().replace("\\", "/")
				i += 1
			_:
				if arg.begins_with("--") or target != "":
					printerr(USAGE)
					quit(2)
					return
				target = arg
	if target == "":
		printerr(USAGE)
		quit(2)
		return

	var ok = TestCI.test_package(ReleaseCli.to_res_path(target), refresh, local, tree)
	print(OUTPUT_PREFIX + JSON.stringify(TestCI.report))
	quit(0 if ok else 1)
