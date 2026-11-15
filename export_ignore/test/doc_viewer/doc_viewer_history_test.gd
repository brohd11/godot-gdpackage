@tool
extends EditorScript

## Tests for the doc viewer's history and its sidebar/contents switching, on a three-doc fixture.
## The viewer is parked under the tree root for the run, since it only builds itself in _ready.
## Scroll restore needs frames to pass, so only page and stack state are checked.
##
##     load("res://addons/gdpackage/export_ignore/test/doc_viewer/doc_viewer_history_test.gd").run_tests()

const DocViewer = preload("res://addons/gdpackage/src/components/doc_viewer/doc_viewer.gd")

const FIXTURES = "res://addons/gdpackage/export_ignore/test/doc_viewer/fixtures/history"
const NARROW = Vector2(200, 600)
const WIDE = Vector2(4000, 600)

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.is_inside_tree():
		_failures.append("no scene tree to host the viewer")
	else:
		_test_landing(tree.root)
		_test_history(tree.root)
		_test_reset(tree.root)

	var output:Array[String] = []
	output.append("doc_viewer_history: %d passed, %d failed" % [_passed, _failures.size()])
	for failure in _failures:
		output.append("  FAIL  " + failure)

	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _new_viewer(host:Node, size:Vector2):
	var viewer = DocViewer.new()
	viewer.docs_path = FIXTURES
	host.add_child(viewer)
	viewer.size = size
	return viewer


static func _doc(viewer, file:String) -> int:
	return viewer._index_of(FIXTURES.path_join(file))


static func _test_landing(host:Node) -> void:
	var viewer = _new_viewer(host, Vector2.ZERO)
	_check("landing: three docs found", viewer._docs.size(), 3)
	_check("landing: zero width opens the contents page", viewer._current, DocViewer._PAGE_CONTENTS)
	_check("landing: no sidebar beside the contents page", viewer._sidebar.visible, false)
	_check("landing: no contents button on the contents page", viewer._contents_button.visible, false)

	viewer.size = WIDE
	_check("landing: widening swaps in the first doc", viewer._current, 0)
	_check("landing: the swap is not history", viewer._back.size(), 0)
	_check("landing: sidebar shown when wide", viewer._sidebar.visible, true)
	_check("landing: contents button hidden beside the sidebar", viewer._contents_button.visible, false)

	viewer.size = NARROW
	_check("narrow: sidebar hidden", viewer._sidebar.visible, false)
	_check("narrow: contents button back", viewer._contents_button.visible, true)
	_check("narrow: stays on the doc", viewer._current, 0)

	viewer.show_contents()
	viewer.size = WIDE
	_check("wide: a contents page the reader chose is kept", viewer._current, DocViewer._PAGE_CONTENTS)
	_check("wide: still no sidebar beside it", viewer._sidebar.visible, false)
	viewer.free()

	viewer = _new_viewer(host, WIDE)
	viewer.reload()
	_check("reload: already wide opens the first doc", viewer._current, 0)
	viewer.free()


static func _test_history(host:Node) -> void:
	var viewer = _new_viewer(host, NARROW)
	var a = _doc(viewer, "a.md")
	var b = _doc(viewer, "b.md")
	var c = _doc(viewer, "c.md")
	_check("history: starts empty", [viewer._back.size(), viewer._forward.size()], [0, 0])
	_check("history: back disabled when empty", viewer._back_button.disabled, true)

	viewer._on_link_activated(FIXTURES.path_join("a.md"))
	viewer._on_link_activated("b.md")
	_check("link: opens the doc", viewer._current, b)
	_check("link: pushes where it came from", viewer._back.size(), 2)
	_check("link: back enabled", viewer._back_button.disabled, false)

	viewer._on_link_activated("#section")
	_check("anchor: stays on the page", viewer._current, b)
	_check("anchor: still history", viewer._back.size(), 3)
	_check("anchor: carries the anchor", viewer._pending_scroll.get(DocViewer._LOC_ANCHOR), "section")

	viewer.go_back()
	_check("back: out of the anchor jump", [viewer._current, viewer._forward.size()], [b, 1])
	viewer.go_back()
	_check("back: to the previous doc", viewer._current, a)
	_check("back: forward enabled", viewer._forward_button.disabled, false)
	viewer.go_back()
	_check("back: to the contents page", viewer._current, DocViewer._PAGE_CONTENTS)
	viewer.go_back()
	_check("back: no-op at the start", [viewer._current, viewer._back.size()], [DocViewer._PAGE_CONTENTS, 0])

	viewer.go_forward()
	viewer.go_forward()
	_check("forward: replays", viewer._current, b)
	_check("forward: one left", viewer._forward.size(), 1)

	viewer._on_link_activated("c.md")
	_check("new link: opens it", viewer._current, c)
	_check("new link: drops the forward stack", viewer._forward.size(), 0)

	viewer._next_button.pressed.emit()
	_check("footer: next at the end is a no-op", [viewer._current, viewer._back.size()], [c, 3])
	viewer._prev_button.pressed.emit()
	_check("footer: prev is history too", [viewer._current, viewer._back.size()], [b, 4])
	viewer.free()


static func _test_reset(host:Node) -> void:
	var viewer = _new_viewer(host, NARROW)
	viewer._on_link_activated(FIXTURES.path_join("a.md"))
	viewer.reload()
	_check("reload: clears history", [viewer._back.size(), viewer._forward.size()], [0, 0])

	viewer._on_link_activated(FIXTURES.path_join("a.md"))
	viewer.clear()
	_check("clear: clears history", viewer._back.size(), 0)
	_check("clear: empty contents page", [viewer._current, viewer._toc.text], [DocViewer._PAGE_CONTENTS, DocViewer.EMPTY_MESSAGE])
	viewer.free()


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
		return
	_failures.append("%s — expected %s, got %s" % [label, var_to_str(expected), var_to_str(actual)])
