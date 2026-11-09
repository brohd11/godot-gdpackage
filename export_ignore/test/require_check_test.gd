@tool
extends EditorScript
## require check --tags: declared requires (cfg, compile_require, test_require) looked up the way a
## build fetches them, with the reason when one can't be, and a note when a checkout is past its tag.

const RequireCheck = preload("res://addons/gdpackage/src/class/release/require_check.gd")
const DepResolverTest = preload("res://addons/gdpackage/export_ignore/test/dep_resolver_test.gd")
const ROOT = "user://pe_require_check_tests"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_check_tags()
	_test_dependency_graph()
	var output:Array[String] = ["require_check: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_check_tags() -> void:
	var root = ProjectSettings.globalize_path(ROOT)
	_write(root.path_join("pkg/plugin.cfg"), '[plugin]\nversion="0.1.0"\nrequire=[\n"a/ok@v1.0.0",\n"a/missing@v2",\n"a/toggle@1.0.0",\n]\n')
	_write(root.path_join("pkg/_export_ignore/plugin_export.yml"), 'export_root: "x"\ncompile_require: ["a/peer@v1"]\n' +
		'test_require:\n  - "@require"\n  - "a/rel/release@v1:*-linux.zip"\n  - "a/multi/release@v1"\nexports: []\n')
	_write(root.path_join("ok/version.cfg"), '[plugin]\nversion="1.2.0"\n')

	var f = DepResolverTest.FakeFetcher.new()
	f.add("a/ok", "v1.0.0", {})
	f.add("a/toggle", "v1.0.0", {})
	f.add("a/peer", "v1", {})
	f.add_release("a/rel", "v1", {}, ["rel-linux.zip", "rel-macos.zip"])
	f.add_release("a/multi", "v1", {}, ["m-linux.zip", "m-macos.zip"])
	var result = RequireCheck.check_tags(root.path_join("pkg"), f, {"github.com/a/ok": root.path_join("ok")})
	_check("no errors", result.errors, [])
	var rows = {}
	for row in result.rows:
		rows[row.spec] = row
	_check("every declared spec once, with where it came from", result.rows.map(func(r): return [r.key, r.spec]), [
		["build", "a/ok@v1.0.0"], ["build", "a/missing@v2"], ["build", "a/toggle@1.0.0"],
		["compile", "a/peer@v1"], ["test", "a/rel/release@v1:*-linux.zip"], ["test", "a/multi/release@v1"]])
	_check("a fetchable tag is ok", [rows["a/ok@v1.0.0"].ok, rows["a/ok@v1.0.0"].tag], [true, "v1.0.0"])
	_check("a missing tag fails", rows["a/missing@v2"].ok, false)
	_check("the v-toggled tag is found", rows["a/toggle@1.0.0"].tag, "v1.0.0")
	_check("a pinned release asset is ok", rows["a/rel/release@v1:*-linux.zip"].ok, true)
	var multi = rows["a/multi/release@v1"]
	_check("an unpinned multi-asset release fails with the choices", not multi.ok and "m-macos.zip" in multi.reason, true)
	_check("a newer checkout is noted, not failed", [rows["a/ok@v1.0.0"].note, rows["a/ok@v1.0.0"].ok], ["checkout is at v1.2.0", true])
	var text = RequireCheck.format(result)
	_check("format marks failures", "FAIL build   a/missing@v2" in text and "ok   build   a/ok@v1.0.0" in text, true)
	_check("no cfg is an error", RequireCheck.check_tags(root.path_join("ok/nope"), f, {}).errors.size(), 1)
	_remove(root)


static func _test_dependency_graph() -> void:
	var root = ProjectSettings.globalize_path(ROOT)
	var dir = root.path_join("graph")
	var cfg = '[package]\nversion="1"\nurl="https://github.com/me/a"\nrequire=["me/c@0.2.0", "me/b@v1"]\n'
	_write(dir.path_join("package.cfg"), cfg)
	var f = DepResolverTest.FakeFetcher.new()
	f.add("me/b", "v1", {"package.cfg": '[package]\npath="addons/b"\nrequire=["me/c@v0.2.1", "me/a@v1"]\n'})
	f.add("me/c", "v0.2.0", {"package.cfg": '[package]\npath="addons/c"\n'})
	f.add("me/c", "v0.2.1", {"package.cfg": '[package]\npath="addons/c"\n'})
	var result = RequireCheck.check_tags(dir, f, {})
	_check("graph: resolves without a root checkout or root tag", result.errors, [])
	_check("graph: fetchable direct rows remain ok", result.rows.all(func(row): return row.ok), true)
	_check("graph: duplicate build and test declarations warn once", result.warnings.size(), 1)
	var text = RequireCheck.format(result)
	_check("graph: warning names declaration and chain " + text,
		"WARN me/a@worktree declares me/c@0.2.0" in text and "me/a@worktree -> me/b@v1 -> me/c@v0.2.1" in text, true)

	# Without identity metadata, the directory still names the root for diagnostics.
	f.add("me/b", "v1", {"package.cfg": '[package]\npath="addons/b"\nrequire=["me/c@v0.2.1"]\n'})
	_write(dir.path_join("package.cfg"), cfg.replace('url="https://github.com/me/a"\n', ""))
	result = RequireCheck.check_tags(dir, f, {})
	_check("graph: no origin or url needed", [result.errors, result.warnings.size()], [[], 1])

	for key in ["compile_require", "test_require"]:
		_write(dir.path_join("package.cfg"), '[package]\nrequire=["me/c@v0.2.0"]\n')
		_write(dir.path_join("export_ignore/plugin_export.yml"), '%s: ["me/b@v1"]\n' % key)
		result = RequireCheck.check_tags(dir, f, {})
		_check("graph: %s participates" % key, [result.errors, result.warnings.size()], [[], 1])

	_write(dir.path_join("package.cfg"), cfg)
	DirAccess.remove_absolute(dir.path_join("export_ignore/plugin_export.yml"))
	f.add("me/b", "v1", {"package.cfg": '[package]\npath="addons/b"\nrequire=["me/missing@v1"]\n'})
	result = RequireCheck.check_tags(dir, f, {})
	_check("graph: transitive missing tag fails while direct rows pass",
		result.rows.all(func(row): return row.ok) and not result.errors.is_empty() and "me/missing" in str(result.errors), true)
	_check("graph: invalid graph has no warnings", result.warnings, [])

	f.add("me/b", "v1", {"package.cfg": '[package]\npath="addons/b"\nrequire=["me/c@v2.0.0"]\n'})
	f.add("me/c", "v2.0.0", {"package.cfg": '[package]\npath="addons/c"\n'})
	result = RequireCheck.check_tags(dir, f, {})
	_check("graph: incompatible majors fail", "share a major line" in str(result.errors), true)

	f.add("me/b", "v1", {})
	result = RequireCheck.check_tags(dir, f, {})
	_check("graph: fetched tree without a package fails", result.errors.is_empty(), false)
	_remove(root)


static func _write(path:String, content:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)


static func _remove(dir:String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
		return
	_failures.append("%s (expected %s, got %s)" % [label, expected, got])
