@tool
extends EditorScript

## Tests for the doc viewer's Tools menu registration, run against a bare PopupMenu standing in
## for the editor's. The submenu is shared by every packaged copy of the viewer, so what matters
## is that it is created once, holds one item per plugin, and is gone when the last one leaves.
##
##     load("res://addons/gdpackage/export_ignore/test/doc_viewer/doc_menu_test.gd").run_tests()

const DocViewer = preload("res://addons/gdpackage/src/components/doc_viewer/doc_viewer.gd")

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	_test_register()
	_test_unregister()

	var output:Array[String] = []
	output.append("doc_menu: %d passed, %d failed" % [_passed, _failures.size()])
	for failure in _failures:
		output.append("  FAIL  " + failure)

	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_register() -> void:
	var tools = PopupMenu.new()
	tools.add_item("Existing")

	DocViewer._register_in(tools, "Alpha", "res://addons/alpha/")
	var menu = DocViewer._get_docs_menu(tools, false)
	_check("register: submenu created", menu != null, true)
	_check("register: submenu item added", tools.item_count, 2)
	_check("register: item points at the submenu", tools.get_item_submenu_node(1) == menu, true)
	_check("register: plugin item", menu.get_item_text(0), "Alpha")
	_check("register: metadata is callable", menu.get_item_metadata(0) is Callable, true)

	DocViewer._register_in(tools, "Beta", "res://addons/beta/")
	_check("register: second plugin shares the submenu", tools.item_count, 2)
	_check("register: second item", menu.item_count, 2)

	DocViewer._register_in(tools, "Alpha", "res://addons/alpha/")
	_check("register: same name is not duplicated", menu.item_count, 2)
	_check("register: handler connected once", menu.index_pressed.get_connections().size(), 1)

	DocViewer._unregister_in(tools, "Alpha")
	DocViewer._unregister_in(tools, "Beta")
	tools.free()


static func _test_unregister() -> void:
	var tools = PopupMenu.new()
	tools.add_item("Existing")
	DocViewer._register_in(tools, "Alpha", "res://addons/alpha/")
	DocViewer._register_in(tools, "Beta", "res://addons/beta/")
	var menu = DocViewer._get_docs_menu(tools, false)

	DocViewer._unregister_in(tools, "Alpha")
	_check("unregister: item removed", menu.item_count, 1)
	_check("unregister: submenu kept while in use", DocViewer._get_docs_menu(tools, false) == menu, true)
	_check("unregister: handler kept while in use", menu.index_pressed.get_connections().size(), 1)

	DocViewer._unregister_in(tools, "Missing")
	_check("unregister: unknown name is a no-op", menu.item_count, 1)

	DocViewer._unregister_in(tools, "Beta")
	_check("unregister: last one removes the submenu", DocViewer._get_docs_menu(tools, false), null)
	_check("unregister: and its item", tools.item_count, 1)

	# A plugin reload unregisters and registers in the same frame.
	DocViewer._register_in(tools, "Alpha", "res://addons/alpha/")
	_check("re-register: fresh submenu", DocViewer._get_docs_menu(tools, false) != null, true)
	DocViewer._unregister_in(tools, "Alpha")
	tools.free()


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
		return
	_failures.append("%s — expected %s, got %s" % [label, var_to_str(expected), var_to_str(actual)])
