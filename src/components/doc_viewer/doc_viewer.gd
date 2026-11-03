extends VBoxContainer
## Documentation browser for a plugin: contents page listing every doc, then one page per doc.
##
## Point it at an addon directory and it finds the docs itself - the packaged ".doc" folder, the
## "_export_ignore/doc" (or "export_ignore/doc") folder it came from in a dev project, or the plugin's README as a last
## resort. Point it at a single file instead and that file is the whole viewer, no folder scan.
## Engine-only and plugin agnostic, so it can be lifted out of here as is.

const Parser = preload("res://addons/gdpackage/src/components/doc_viewer/markdown_parser.gd")
const DocIndex = preload("res://addons/gdpackage/src/components/doc_viewer/doc_index.gd")
const MarkdownView = preload("res://addons/gdpackage/src/components/doc_viewer/markdown_view.gd")

const CONTENTS_TITLE = "Contents"
const EMPTY_MESSAGE = "No documentation found."

const _WINDOW_SIZE = Vector2i(900, 720)
## Negative page ids, so every doc keeps its own position in the flat list as its id.
const _PAGE_CONTENTS = -1
## A doc reached by link that the index does not hold, kept apart so following one does not
## discard the index it was followed from.
const _PAGE_EXTERNAL = -2

signal doc_opened(path:String)

## Addon directory, a doc directory, or a single file.
var docs_path:String = "":
	set = set_docs_path
## Optional (lang:String) -> SyntaxHighlighter, handed straight to the markdown view.
var highlighter_provider:Callable:
	set = set_highlighter_provider

var _docs:Array = []
var _doc_dir:String = ""
var _current:int = _PAGE_CONTENTS
var _external_path:String = ""

var _title_label:Label
var _contents_button:Button
var _scroll:ScrollContainer
var _toc:RichTextLabel
var _view:MarkdownView
var _footer:HBoxContainer
var _prev_button:Button
var _next_button:Button


func _init() -> void:
	name = "Docs"


## Opens the viewer in its own window, which frees itself when closed. Returns the window, or
## null when there is nowhere to attach it.
static func open(path:String, parent:Node = null) -> Window:
	if parent == null:
		parent = _default_parent()
	if parent == null:
		push_error("DocViewer.open: no parent node to attach the window to.")
		return null

	var viewer = new()
	viewer.docs_path = path

	var window = Window.new()
	window.title = "Documentation - %s" % path.trim_suffix("/").get_file()
	window.close_requested.connect(window.queue_free)
	window.add_child(viewer)

	parent.add_child(window)
	viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.popup_centered(_WINDOW_SIZE * _ui_scale())
	return window


static func _default_parent() -> Node:
	if Engine.is_editor_hint():
		return EditorInterface.get_base_control()
	return null


static func _ui_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0


func _ready() -> void:
	var header = HBoxContainer.new()
	add_child(header)

	_contents_button = Button.new()
	header.add_child(_contents_button)
	_contents_button.text = "☰ " + CONTENTS_TITLE
	_contents_button.focus_mode = Control.FOCUS_NONE
	_contents_button.pressed.connect(show_contents)

	_title_label = Label.new()
	header.add_child(_title_label)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	add_child(_scroll)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var margin = MarginContainer.new()
	_scroll.add_child(margin)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi(8 * _ui_scale()))

	var page = VBoxContainer.new()
	margin.add_child(page)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_toc = RichTextLabel.new()
	page.add_child(_toc)
	_toc.bbcode_enabled = true
	_toc.fit_content = true
	_toc.selection_enabled = true
	_toc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toc.meta_clicked.connect(_on_link_activated)

	_view = MarkdownView.new()
	page.add_child(_view)
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.highlighter_provider = highlighter_provider
	_view.link_activated.connect(_on_link_activated)

	_footer = HBoxContainer.new()
	add_child(_footer)

	_prev_button = Button.new()
	_footer.add_child(_prev_button)
	_prev_button.focus_mode = Control.FOCUS_NONE
	_prev_button.pressed.connect(func(): _show_doc(_current - 1))

	_footer.add_spacer(false)

	_next_button = Button.new()
	_footer.add_child(_next_button)
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.pressed.connect(func(): _show_doc(_current + 1))

	reload()


func set_docs_path(value:String) -> void:
	docs_path = value
	if is_node_ready():
		reload()


func set_highlighter_provider(value:Callable) -> void:
	highlighter_provider = value
	if is_instance_valid(_view):
		_view.highlighter_provider = value


## Shows one file as the whole viewer - no folder scan, no contents page.
func display(path:String) -> void:
	docs_path = path

func clear(): # maybe modify show_contents to reduce this duplication
	_current = _PAGE_CONTENTS
	_external_path = ""
	_view.hide()
	_view.clear()
	_toc.show()
	_toc.text = EMPTY_MESSAGE
	_title_label.text = CONTENTS_TITLE
	_update_nav()
	pass

## Rescans the doc folder and returns to whichever page makes sense for what was found.
func reload() -> void:
	# Nothing to draw into yet - _ready calls this again once the controls exist.
	if not is_node_ready():
		return
	_docs = []
	_doc_dir = ""
	_external_path = ""

	if _is_file(docs_path):
		# A file path is the whole index, so nothing is scanned or guessed at.
		_docs = DocIndex.single(docs_path)
	else:
		_doc_dir = DocIndex.find_doc_dir(docs_path)
		if _doc_dir != "":
			_docs = DocIndex.scan(_doc_dir)
		if _docs.is_empty():
			# No doc folder, or an empty one - the plugin's readme is better than nothing.
			var readme = DocIndex.find_readme(docs_path)
			if readme != "":
				_docs = DocIndex.single(readme)

	if _docs.size() == 1:
		_show_doc(0)
	else:
		show_contents()


func show_contents() -> void:
	_current = _PAGE_CONTENTS
	_external_path = ""
	_view.hide()
	_view.clear()
	_toc.show()
	_toc.text = _build_contents()
	_title_label.text = CONTENTS_TITLE
	_update_nav()


func _show_doc(index:int) -> void:
	if index < 0 or index >= _docs.size():
		return
	var doc:Dictionary = _docs[index]
	_external_path = ""
	_current = index
	_show_page(doc[DocIndex.KEY_PATH], doc[DocIndex.KEY_TITLE])


## A doc the index does not hold, reached by following a link out of one that it does.
func _show_external(path:String) -> void:
	_external_path = path
	_current = _PAGE_EXTERNAL
	_show_page(path, DocIndex.title_for(path))


func _show_page(path:String, title:String) -> void:
	_toc.hide()
	_view.show()
	_view.set_file(path)
	_title_label.text = title
	_update_nav()
	_scroll.set_deferred("scroll_vertical", 0)
	doc_opened.emit(path)


## Contents as one bbcode block: the depth-first order already reads as a tree once each entry is
## indented by its depth, with a bold row wherever the walk enters a new directory.
func _build_contents() -> String:
	if _docs.is_empty():
		return EMPTY_MESSAGE

	var lines:Array[String] = []
	var current_dir:PackedStringArray = []
	for doc in _docs:
		var segments = String(doc[DocIndex.KEY_REL]).get_base_dir().split("/", false)
		if segments != current_dir:
			var shared := 0
			while shared < segments.size() and shared < current_dir.size() and segments[shared] == current_dir[shared]:
				shared += 1
			for i in range(shared, segments.size()):
				lines.append(_indented("[b]%s[/b]" % segments[i].capitalize(), i))
			current_dir = segments
		var link = "[url=%s]%s[/url]" % [doc[DocIndex.KEY_PATH], doc[DocIndex.KEY_TITLE]]
		lines.append(_indented(link, doc[DocIndex.KEY_DEPTH]))

	return "\n".join(lines)


## Every [indent] closed on its own line, or the rows after a nested one inherit its depth.
func _indented(text:String, depth:int) -> String:
	if depth <= 0:
		return text
	return "[indent]".repeat(depth) + text + "[/indent]".repeat(depth)


func _update_nav() -> void:
	# One doc means there is nothing to navigate between and no contents worth showing.
	var multiple = _docs.size() > 1
	_footer.visible = multiple
	_contents_button.visible = multiple and _current != _PAGE_CONTENTS

	if not multiple:
		return
	# An external page sits outside the running order, so it can only be stepped away from.
	var external = _current == _PAGE_EXTERNAL
	_prev_button.disabled = external or _current <= 0
	_next_button.disabled = external or _current >= _docs.size() - 1
	_prev_button.text = "◀  " + _doc_title(_current - 1)
	_next_button.text = _doc_title(_current + 1) + "  ▶"


func _doc_title(index:int) -> String:
	if index < 0 or index >= _docs.size():
		return ""
	return _docs[index][DocIndex.KEY_TITLE]


func _on_link_activated(meta:String) -> void:
	if meta.begins_with("http://") or meta.begins_with("https://"):
		OS.shell_open(meta)
		return

	# Anchors are not resolved yet, but a link carrying one still opens its doc.
	var target = meta.get_slice("#", 0)
	if target == "":
		return
	if not target.contains("://") and not target.begins_with("/"):
		target = _current_dir().path_join(target).simplify_path()

	var index = _index_of(target)
	if index != -1:
		_show_doc(index)
		return

	if not FileAccess.file_exists(target):
		push_warning("DocViewer: unresolved link '%s'" % meta)
		return

	# A doc outside the index still opens; the contents button is how you get back.
	if target.get_extension().to_lower() == "md":
		_show_external(target)
		return

	# Anything else is a project file the reader is being pointed at, not something to render.
	if target.begins_with("res://") and Engine.is_editor_hint():
		EditorInterface.get_file_system_dock().navigate_to_path(target)
		return
	OS.shell_open(ProjectSettings.globalize_path(target))


## Directory relative links resolve against - the page showing, or the doc root on the contents.
func _current_dir() -> String:
	if _current == _PAGE_EXTERNAL:
		return _external_path.get_base_dir()
	if _current >= 0 and _current < _docs.size():
		return String(_docs[_current][DocIndex.KEY_PATH]).get_base_dir()
	return _doc_dir


func _is_file(path:String) -> bool:
	return not DirAccess.dir_exists_absolute(path) and FileAccess.file_exists(path)


func _index_of(path:String) -> int:
	for i in range(_docs.size()):
		if _docs[i][DocIndex.KEY_PATH] == path:
			return i
	return -1
