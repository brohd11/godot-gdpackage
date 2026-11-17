@tool
extends EditorScript
## MinVersionStamp: the raise-only rule, folding stored package values into the scan, and the cfg
## write (replace, never a second line; legacy minimum_version dropped). Temp cfgs, no crawl.
##
##     load("res://addons/gdpackage/export_ignore/test/min_version_stamp_test.gd").run_tests()

const MinVersionStamp = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/min_version_stamp.gd")
const ROOT = "user://gdpackage_min_version_stamp_tests"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_decide()
	_test_set_in_text()
	_test_package_dir()
	_test_compute_and_stamp()
	var output:Array[String] = ["min_version_stamp: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_decide() -> void:
	_check("decide: unset is written", MinVersionStamp.decide("", "4.4"), {"value": "4.4", "write": true, "kept": false})
	_check("decide: higher raises", MinVersionStamp.decide("4.3", "4.4"), {"value": "4.4", "write": true, "kept": false})
	_check("decide: equal is a no-op", MinVersionStamp.decide("4.4", "4.4"), {"value": "4.4", "write": false, "kept": false})
	_check("decide: lower keeps the stored value", MinVersionStamp.decide("4.5", "4.4"), {"value": "4.5", "write": false, "kept": true})
	_check("decide: allow_lower lowers", MinVersionStamp.decide("4.5", "4.4", true), {"value": "4.4", "write": true, "kept": false})
	_check("decide: 4.10 > 4.9", MinVersionStamp.decide("4.9", "4.10"), {"value": "4.10", "write": true, "kept": false})
	_check("decide: unparseable computed never replaces", MinVersionStamp.decide("4.5", "", true), {"value": "4.5", "write": false, "kept": false})


static func _test_set_in_text() -> void:
	_check("set_in_text: legacy dropped, new key beside version",
		MinVersionStamp.set_in_text('[plugin]\nname="p"\nversion="1"\nminimum_version="4.3"\n', "4.4"),
		'[plugin]\nname="p"\nversion="1"\nminimum_engine_version="4.4"\n')
	var once = MinVersionStamp.set_in_text('[package]\nversion="1"\nurl="u"\n', "4.4")
	_check("set_in_text: second write replaces, one line", MinVersionStamp.set_in_text(once, "4.5"),
		'[package]\nversion="1"\nminimum_engine_version="4.5"\nurl="u"\n')


static func _test_package_dir() -> void:
	var cache = {}
	_check("package_dir: nearest cfg dir", MinVersionStamp.package_dir("res://addons/_lib/yaml_parser/yaml.gd", cache),
		"res://addons/_lib/yaml_parser")
	_check("package_dir: no package", MinVersionStamp.package_dir("res://project.godot", cache), "")
	_check("package_dirs_for: distinct, packageless dropped", MinVersionStamp.package_dirs_for(
		["res://addons/_lib/yaml_parser/yaml.gd", "res://addons/_lib/yaml_parser/LICENSE", "res://project.godot"], cache),
		["res://addons/_lib/yaml_parser"])


static func _test_compute_and_stamp() -> void:
	_remove_dir(ProjectSettings.globalize_path(ROOT))
	var target = ROOT.path_join("target")
	var dep_hi = ROOT.path_join("dep_hi")
	var dep_lo = ROOT.path_join("dep_lo")
	_write(target.path_join("package.cfg"), '[package]\nversion="1.0.0"\nurl="u"\n')
	_write(dep_hi.path_join("package.cfg"), '[package]\nversion="2"\nminimum_engine_version="9.1"\n')
	_write(dep_lo.path_join("package.cfg"), '[package]\nversion="2"\n')

	var r = MinVersionStamp.compute([], [dep_lo, dep_hi])
	if not r.has_index:
		_failures.append("compute: no API index, compute/stamp checks skipped")
		return
	_check("compute: a stored dep value beats the scan", [r.version, r.via], ["9.1", dep_hi])
	_check("compute: only cfgs with the key are listed", r.stored, {dep_hi: "9.1"})

	var s = MinVersionStamp.stamp(target, [], [target, dep_hi, dep_lo])
	_check("stamp: written from the dep", [s.ok, s.changed], [true, true])
	_check("stamp: cfg line beside version", _read(target.path_join("package.cfg")),
		'[package]\nversion="1.0.0"\nminimum_engine_version="9.1"\nurl="u"\n')
	_check("stamp: second run is a no-op", MinVersionStamp.stamp(target, [], [dep_hi]).changed, false)

	var kept = MinVersionStamp.stamp(target, [], [])
	_check("stamp: lower computed keeps the stored value", [kept.changed, MinVersionStamp.stored_value(target)], [false, "9.1"])
	_check("stamp: kept is reported", kept.line.contains("kept 9.1"), true)
	var lowered = MinVersionStamp.stamp(target, [], [], true)
	_check("stamp: allow_lower lowers to the scan", [lowered.changed, MinVersionStamp.stored_value(target)], [true, r.scanned])

	_check("stamp: missing cfg is an error", MinVersionStamp.stamp(ROOT.path_join("none"), [], []).ok, false)

	_check("fold_stored: max and via", MinVersionStamp.fold_stored("4.4", [dep_lo, dep_hi]), {"version": "9.1", "stored": {dep_hi: "9.1"}, "via": dep_hi})
	_check("fold_stored: scan wins over lower values", MinVersionStamp.fold_stored("9.5", [dep_hi]).via, "")
	# root boundary: the cfg at ROOT itself sits above `dep_lo/inner`'s root and must not be found
	_write(ROOT.path_join("package.cfg"), '[package]\nversion="0"\n')
	_write(dep_lo.path_join("x/inner/a.gd"), "")
	_check("package_dir: walks up to the nearest cfg", MinVersionStamp.package_dir(dep_lo.path_join("x/inner/a.gd"), {}, ROOT), dep_lo)
	_check("package_dir: stops at root", MinVersionStamp.package_dir(dep_lo.path_join("x/inner/a.gd"), {}, dep_lo.path_join("x")), "")
	_remove_dir(ProjectSettings.globalize_path(ROOT))


static func _write(path:String, text:String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


static func _read(path:String) -> String:
	return FileAccess.get_file_as_string(path)


static func _remove_dir(path:String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_dir(path.path_join(d))
	DirAccess.remove_absolute(path)


static func _check(label:String, got, expected) -> void:
	if got == expected:
		_passed += 1
	else:
		_failures.append("%s (expected %s, got %s)" % [label, expected, got])
