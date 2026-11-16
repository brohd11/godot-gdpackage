@tool
extends EditorScript
## export config `external:` resolution: dirs as-is, specs via the workspace install map, cfg url=,
## then git origin, and the merge into the released cfg's require.

const ExternalDeps = preload("res://addons/gdpackage/src/class/export/external_deps.gd")
const DepResolver = preload("res://addons/gdpackage/src/class/release/dep_resolver.gd")
const Discovery = preload("res://addons/gdpackage/src/class/export/package_discovery.gd")
const Runner = preload("res://addons/gdpackage/src/class/release/release_runner.gd")
const ROOT = "user://pe_external_deps_tests"
const REAL_DIR = "res://addons/gdpackage"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	Runner.remove_dir(ProjectSettings.globalize_path(ROOT))
	Discovery.clear_cache()
	_write("lib_a/package.cfg", '[package]\nversion="1.0.0"\nurl="https://github.com/Owner/Lib-A.git"\n')
	_write("lib_b/plugin.cfg", '[plugin]\nname="B"\n')

	_test_entries()
	_test_resolve()
	_test_require()

	Runner.remove_dir(ProjectSettings.globalize_path(ROOT))
	Discovery.clear_cache()
	var output:Array[String] = ["external_deps: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void:
	print("\n".join(run_tests().output))


static func _test_entries() -> void:
	_check("entries: list trimmed, blanks and non-strings dropped",
		ExternalDeps.entries([" a/b ", "", 3, "res://x"]), ["a/b", "res://x"])
	_check("entries: single string", ExternalDeps.entries("a/b@v1"), ["a/b@v1"])
	_check("entries: absent", ExternalDeps.entries(null), [])


static func _test_resolve() -> void:
	var no_git = {} # an empty dev_repos keeps the git fallback from scanning the real project
	var r = ExternalDeps.resolve([REAL_DIR, REAL_DIR + "/"], ROOT, no_git)
	_check("dir: trailing slash, deduplicated", r.dirs, [REAL_DIR + "/"])
	_check("dir: not a spec", r.specs, [])

	r = ExternalDeps.resolve(["res://addons/does_not_exist"], ROOT, no_git)
	_check("dir: missing is an error", r.errors.size(), 1)

	r = ExternalDeps.resolve(["not a spec"], ROOT, no_git)
	_check("malformed entry is an error", r.errors.size(), 1)

	r = ExternalDeps.resolve(["owner/lib-a@v1.0.0"], ROOT, no_git)
	_check("spec: matched by cfg url=, any case", r.dirs, [ROOT.path_join("lib_a") + "/"])
	_check("spec: kept for the require", r.specs, ["owner/lib-a@v1.0.0"])
	_check("spec: no errors", r.errors, [])

	var lib_b_id = DepResolver.parse_dep("owner/lib-b").repo_id
	r = ExternalDeps.resolve(["owner/lib-b@v2"], ROOT, {lib_b_id: ROOT.path_join("lib_b")})
	_check("spec: git origin fallback", r.dirs, [ROOT.path_join("lib_b") + "/"])

	r = ExternalDeps.resolve(["owner/lib-c@v1", "owner/lib-a"], ROOT, no_git)
	_check("spec: unresolved is an error", r.errors.size(), 1)
	_check("spec: unresolved left out of specs", r.specs, ["owner/lib-a"])

	var lib_a_id = DepResolver.parse_dep("owner/lib-a").repo_id
	_write("installed.json", JSON.stringify({lib_a_id: ROOT.path_join("lib_b")}))
	r = ExternalDeps.resolve(["owner/lib-a/release@v1"], ROOT, no_git, ROOT.path_join("installed.json"))
	_check("spec: workspace install map wins over url=", r.dirs, [ROOT.path_join("lib_b") + "/"])
	_check("spec: /release kept as written", r.specs, ["owner/lib-a/release@v1"])

	_check("dir_repo_id: from url=", ExternalDeps.dir_repo_id(ROOT.path_join("lib_a")),
		DepResolver.parse_dep("owner/lib-a").repo_id)
	_check("dir_repo_id: no url=", ExternalDeps.dir_repo_id(ROOT.path_join("lib_b")), "")


static func _test_require() -> void:
	_check("merge: repo already listed in another spelling is skipped",
		ExternalDeps.merge_require(["owner/lib-a@v1"], ["Owner/Lib-A@v2", "x/y@v1"]), ["owner/lib-a@v1", "x/y@v1"])
	_check("merge: into empty", ExternalDeps.merge_require([], ["x/y"]), ["x/y"])


static func _write(rel:String, text:String) -> void:
	var path = ROOT.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
		return
	_failures.append("%s (expected %s, got %s)" % [label, expected, got])
