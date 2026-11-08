@tool
extends EditorScript

## Tests for the release export's toolchain lookup: version pinning, release asset urls and
## cached remote toolchains. Downloads are stubbed so fallback and failure diagnostics need no
## network, and cache hits must never invoke curl.
##
##     load("res://addons/gdpackage/export_ignore/test/toolchain_test.gd").run_tests()

const Toolchain = preload("res://addons/gdpackage/src/class/release/toolchain.gd")
const ReleaseRunner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")

const DIR = "user://pe_toolchain_tests"

static var _failures:Array[String] = []
static var _passed:int = 0


class MockToolchain extends Toolchain:
	var responses:Array[Dictionary] = []
	var calls:Array[Array] = []

	func _run_curl(args:Array) -> Dictionary:
		calls.append(args)
		if responses.is_empty():
			return {"exit_code": -1, "output": "unexpected download"}
		return responses.pop_front()


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	var root = ProjectSettings.globalize_path(DIR)
	ReleaseRunner.remove_dir(root)

	_test_pick_version()
	_test_asset_urls()
	_test_cached_remote(root)
	_test_downloads(root)
	_test_unzip(root)

	ReleaseRunner.remove_dir(root)
	var output:Array[String] = []
	output.append("toolchain: %d passed, %d failed" % [_passed, _failures.size()])
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_pick_version() -> void:
	_check("pin wins", Toolchain.pick_version({"toolchain": "0.7.2"}, "0.7.4"), "0.7.2")
	_check("blank pin falls back", Toolchain.pick_version({"toolchain": "  "}, "0.7.4"), "0.7.4")
	_check("no pin falls back", Toolchain.pick_version({}, "0.7.4"), "0.7.4")


static func _test_asset_urls() -> void:
	var urls = Toolchain.asset_urls("https://www.github.com/Brohd11/Godot-GDPackage.git", "0.7.4")
	_check("v tag first", urls[0], "https://github.com/Brohd11/Godot-GDPackage/releases/download/v0.7.4/gdpackage-0.7.4.zip")
	_check("bare tag second", urls[1], "https://github.com/Brohd11/Godot-GDPackage/releases/download/0.7.4/gdpackage-0.7.4.zip")
	_check("v in version not doubled", Toolchain.asset_urls("https://github.com/o/r", "v1.0")[0],
		"https://github.com/o/r/releases/download/v1.0/gdpackage-1.0.zip")
	_check("scp remote", Toolchain.asset_urls("git@github.com:o/r.git", "1.0")[0],
		"https://github.com/o/r/releases/download/v1.0/gdpackage-1.0.zip")


## A version already in the cache resolves as-is: trusted, like a mirrored tag.
static func _test_cached_remote(root:String) -> void:
	var cache_root = root.path_join("cache")
	var dir = cache_root.path_join("toolchains/gdpackage-9.9.9")
	_write(dir.path_join("addons/gdpackage/plugin.cfg"), '[plugin]\nversion="9.9.9"\n')
	_write(dir.path_join("gdpackage-9.9.9.zip"), "not really a zip")

	var tc = MockToolchain.new()
	var info = tc.resolve({"toolchain": "v9.9.9"}, cache_root, false)
	_check("cached: resolved " + str(tc.errors), info.is_empty(), false)
	_check("cached: no download", tc.calls.size(), 0)
	if not info.is_empty():
		_check("cached: dir", info.dir, dir.path_join("addons/gdpackage"))
		_check("cached: source", info.source, "remote")
		_check("cached: id is zip hash", info.id, FileAccess.get_sha256(dir.path_join("gdpackage-9.9.9.zip")))

	_write(dir.path_join("addons/gdpackage/plugin.cfg"), '[plugin]\nversion="9.9.8"\n')
	var mismatch = Toolchain.new()
	_check("cached: wrong version rejected", mismatch.resolve({"toolchain": "9.9.9"}, cache_root, false), {})
	_check("cached: mismatch named", mismatch.errors.size() == 1 and "is 9.9.8, expected 9.9.9" in mismatch.errors[0], true)

	var refresh = MockToolchain.new()
	_check("refresh: download required", refresh.resolve({"toolchain": "9.9.9"}, cache_root, true), {})
	_check("refresh: both tags attempted", refresh.calls.size(), 2)
	_check("refresh: failed cache removed", DirAccess.dir_exists_absolute(dir), false)


static func _test_downloads(root:String) -> void:
	var repo = "https://github.com/example/gdpackage"
	var urls = Toolchain.asset_urls(repo, "9.9.9")
	var zip_path = root.path_join("download/toolchain.zip")
	var fallback = MockToolchain.new()
	fallback.responses.assign([
		{"exit_code": 22, "output": "curl: (22) The requested URL returned error: 404\n"},
		{"exit_code": 0, "output": ""},
	])
	_check("download: bare tag succeeds", fallback._download(repo, "9.9.9", zip_path), true)
	_check("download: both tags tried", fallback.calls.map(func(args): return args.back()), urls)
	_check("download: successful fallback has no errors", fallback.errors, [])

	var failed = MockToolchain.new()
	failed.responses.assign([
		{"exit_code": 22, "output": "curl: (22) The requested URL returned error: 504\n"},
		{"exit_code": 28, "output": "curl: (28) Connection timed out\n"},
	])
	_write(zip_path, "partial download")
	_check("download: failure reported", failed._download(repo, "9.9.9", zip_path), false)
	_check("download: partial zip removed", FileAccess.file_exists(zip_path), false)
	_check("download: one combined error", failed.errors.size(), 1)
	var message = "\n".join(failed.errors)
	for detail in ["gdpackage-9.9.9.zip", urls[0], urls[1], "curl exit 22", "504", "curl exit 28", "Connection timed out"]:
		_check("download: diagnostic includes " + detail, message.contains(detail), true)
	_check("download: does not claim release is missing", message.contains("no release"), false)


static func _test_unzip(root:String) -> void:
	var zip_path = root.path_join("unzip/src.zip")
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var packer = ZIPPacker.new()
	packer.open(zip_path)
	for entry in ["gdpackage/sub/a.txt", "__MACOSX/gdpackage/._a.txt", "gdpackage/.DS_Store"]:
		packer.start_file(entry)
		packer.write_file("hello".to_utf8_buffer())
		packer.close_file()
	packer.close()

	var dest = root.path_join("unzip/out")
	_check("unzip ok", ReleaseRunner.unzip(zip_path, dest), "")
	_check("unzip content", FileAccess.get_file_as_string(dest.path_join("gdpackage/sub/a.txt")), "hello")
	_check("unzip skips __MACOSX", DirAccess.dir_exists_absolute(dest.path_join("__MACOSX")), false)
	_check("unzip skips .DS_Store", FileAccess.file_exists(dest.path_join("gdpackage/.DS_Store")), false)
	_check("unzip bad archive", ReleaseRunner.unzip(root.path_join("unzip/missing.zip"), dest).begins_with("could not open"), true)


static func _write(path:String, text:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
		return
	_failures.append("%s (expected %s, got %s)" % [label, expected, got])
