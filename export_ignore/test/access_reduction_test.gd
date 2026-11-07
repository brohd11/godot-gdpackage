@tool
extends EditorScript

## Tests for the access-path reduction planner — what `reduce_access_paths` decides a dotted
## expression should become before anything is rewritten.
##
## Fixtures are written to user:// and scanned with the real collector, so `consumed` comes from
## an actual walk rather than a hand-built edge. The shapes are the ones that exist in this
## project: full chains through generated namespace hubs, chains ending in an inner class, and
## chains whose head is already the deepest file they name.
##
##     load("res://addons/gdpackage/export_ignore/test/access_reduction_test.gd").run_tests()

const DepScanner = preload("uid://dbn0kmkxa7caq") #! resolve DepMap.Scanner
const DepEdge = DepScanner.DepEdge

const DIR = "user://pe_access_reduction_tests/"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	_reset_dir()

	_test_full_chain()
	_test_inner_class_tail()
	_test_head_is_deepest_file()
	_test_local_const_head()
	_test_alias_tail()
	_test_off_by_default()

	_reset_dir()

	var output:Array[String] = []
	output.append("access_reduction: %d passed, %d failed" % [_passed, _failures.size()])
	for failure in _failures:
		output.append("  FAIL  " + failure)

	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


## The shape the whole feature exists for: a two-level hub chain collapsing to the leaf file.
static func _test_full_chain() -> void:
	var leaf = _w("r_leaf.gd", "extends RefCounted\n")
	var mid = _w("r_mid.gd", _hub('const Leaf = preload("%s")\n' % leaf))
	var top = _w("r_top.gd", _hub('const Mid = preload("%s")\n' % mid))
	var user = _w("r_user.gd", "extends RefCounted\nvar v = Hub.Mid.Leaf\n")

	var plan = _plan(user, {"Hub": top})
	_check("full: one reduction", plan.size(), 1)
	var entry = plan.get("Hub.Mid.Leaf", {})
	_check("full: binds the last segment", entry.get("name", ""), "Leaf")
	_check("full: binds to the leaf file", entry.get("path", ""), leaf)
	_check("full: no tail", entry.get("tail", null), [])


## The walk stops at the last real file; the inner class rides along on the rewritten expression.
static func _test_inner_class_tail() -> void:
	var real = _w("r_real.gd", "extends RefCounted\nclass Inner:\n\tpass\n")
	var hub = _w("r_hub2.gd", _hub('const Real = preload("%s")\n' % real))
	var user = _w("r_user2.gd", "extends RefCounted\nvar v = Hub.Real.Inner\n")

	var plan = _plan(user, {"Hub": hub})
	var entry = plan.get("Hub.Real.Inner", {})
	_check("inner: binds the file, not the inner class", entry.get("name", ""), "Real")
	_check("inner: binds to the real file", entry.get("path", ""), real)
	_check("inner: keeps the tail", entry.get("tail", null), ["Inner"])


## `FileSystemSingleton.FileData.FAVORITES_META` in miniature: the head IS the deepest file, so
## reducing would rewrite the expression to itself and would wrongly mark the class unused.
static func _test_head_is_deepest_file() -> void:
	var head = _w("r_head.gd", "extends RefCounted\nclass Data:\n\tconst FLAG = \"x\"\n")
	var user = _w("r_user3.gd", "extends RefCounted\nvar v = Head.Data.FLAG\n")

	var plan = _plan(user, {"Head": head})
	_check("head-deepest: no reduction planned", plan.is_empty(), true)


## A local hub outside the source is as much a pass-through as a global one. One inside it ships
## whole regardless, so nothing is gained by rewriting around it.
static func _test_local_const_head() -> void:
	var leaf = _w("r_leaf4.gd", "extends RefCounted\n")
	var mid = _w("keep/r_mid4.gd", 'const Leaf = preload("%s")\n' % leaf)
	var user = _w("r_user4.gd", 'const M = preload("%s")\nvar v = M.Leaf\n' % mid)

	var entry = _plan(user, {}).get("M.Leaf", {})
	_check("remote hub: planned", entry.get("path", ""), leaf)
	var kept = _plan(user, {}, [DIR + "keep"])
	_check("source hub: not planned", kept.has("M.Leaf"), false)

	# the resolution itself still happened - it is the policy that declines it, not the walk
	var resolved = false
	for edge in _scan(user, {}, [DIR + "keep"]):
		if edge.meta.get(DepEdge.META_RESOLVED_FROM, "") == "M.Leaf":
			resolved = true
			_check("source hub: flagged as not from the class map",
				edge.meta.get(DepEdge.META_HEAD_FROM_CLASS_MAP, true), false)
	_check("source hub: collector still resolved it", resolved, true)

	# a global head reduces wherever it lives
	var hub = _w("keep/r_hub4.gd", _hub('const Leaf = preload("%s")\n' % leaf))
	var user2 = _w("r_user4b.gd", "extends RefCounted\nvar v = Hub.Leaf\n")
	var global = _plan(user2, {"Hub": hub}, [DIR + "keep"]).get("Hub.Leaf", {})
	_check("class head: binds the leaf", global.get("name", ""), "Leaf")
	_check("class head: binds to the leaf file", global.get("path", ""), leaf)


## An alias contributes segments the expression does not show, and they have to land in the tail
## ahead of the expression's own.
static func _test_alias_tail() -> void:
	var leaf = _w("r_leaf6.gd", "extends RefCounted\nclass Inner:\n\tconst V = 1\n")
	var hub = _w("r_hub6.gd", 'const Lib = preload("%s")\nconst Inner = Lib.Inner\nconst Same = Lib\n' % leaf)
	var user = _w("r_user6.gd", "extends RefCounted\nvar v = Hub.Inner.V\nvar w = Hub.Same\n")

	var plan = _plan(user, {"Hub": hub})
	var entry = plan.get("Hub.Inner.V", {})
	_check("alias tail: binds the file's name", entry.get("name", ""), "Lib")
	_check("alias tail: suffix before the tail", entry.get("tail", []), ["Inner", "V"])
	_check("alias tail: lands on the file", entry.get("path", ""), leaf)
	_check("alias tail: plain alias has no tail", plan.get("Hub.Same", {}).get("tail", ["x"]), [])


## With no class map the scanner does no access-path work, so nothing is planned - this is what
## makes the flag genuinely inert when it is off.
static func _test_off_by_default() -> void:
	var leaf = _w("r_leaf5.gd", "extends RefCounted\n")
	var hub = _w("r_hub5.gd", _hub('const Leaf = preload("%s")\n' % leaf))
	var user = _w("r_user5.gd", "extends RefCounted\nvar v = Hub.Leaf\n")

	var scanner = DepScanner.new()
	scanner.max_depth = 1
	scanner.include_missing = false
	scanner.use_project_classes = false
	scanner.resolve_access_paths = false
	scanner.roots = [user]
	var edges = scanner.get_graph().get_out_edges(user)

	var plan = {}
	for edge in edges:
		if edge.meta.has(DepEdge.META_RESOLVED_FROM):
			plan[edge.meta[DepEdge.META_RESOLVED_FROM]] = true
	_check("off: nothing resolved", plan.is_empty(), true)
	# and the hub itself is not reached either, since only class-map lookups would find it
	_check("off: leaf not reached", hub in scanner.get_graph().get_paths(), false)


# --- harness -----------------------------------------------------------------------------

## Mirrors build_dep_scanner() with a class map.
static func _scan(root:String, class_map:Dictionary, keep_dirs:Array = []) -> Array:
	var scanner = DepScanner.new()
	scanner.max_depth = 1
	scanner.include_missing = false
	scanner.use_project_classes = false
	scanner.class_map = class_map
	scanner.resolve_access_paths = true
	scanner.collapse_keep_dirs = keep_dirs
	scanner.roots = [root]
	return scanner.get_graph().get_out_edges(root)


static func _plan(root:String, class_map:Dictionary, keep_dirs:Array = []) -> Dictionary:
	return DepScanner.ScanGD.plan_reductions(_scan(root, class_map, keep_dirs), {})


## The header the Namespace addon writes; the collector flags these files as hubs.
static func _hub(body:String) -> String:
	return "# This file is auto-generated. Do not edit.\n\n" + body


static func _w(rel_path:String, text:String) -> String:
	var path = DIR + rel_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("could not write fixture: " + path)
		return path
	file.store_string(text)
	file.close()
	return path


static func _reset_dir() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		_rm_recursive(DIR)
	DirAccess.make_dir_recursive_absolute(DIR)


static func _rm_recursive(dir:String) -> void:
	var da = DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for d in da.get_directories():
		_rm_recursive(dir.path_join(d) + "/")
	DirAccess.remove_absolute(dir)


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("%s\n          expected: %s\n          actual:   %s" % [label, expected, actual])
