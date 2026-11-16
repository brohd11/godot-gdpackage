extends VBoxContainer
## Documentation browser for a plugin: contents page listing every doc, then one page per doc.
##
## Point it at an addon directory and it finds the docs itself - the packaged ".doc" folder, the
## "_export_ignore/doc" (or "export_ignore/doc") folder it came from in a dev project, or the plugin's README as a last
## resort. Point it at a single file instead and that file is the whole viewer, no folder scan.
## Rendering is MarkdownView's; this side hands it the editor theme's colors, font and icons.

const Parser = preload("uid://ct8civnuqvg81") #! resolve MarkdownView.Parser
const DocIndex = preload("res://addons/gdpackage/src/components/doc_viewer/doc_index.gd")
const MDView = preload("uid://bwtay2k1o6eyg") #! resolve MarkdownView.View

const CONTENTS_TITLE = "Contents"
const EMPTY_MESSAGE = "No documentation found."

## Wide enough at editor scale 1 for the contents sidebar to show.
const _WINDOW_SIZE = Vector2i(1150, 760)
## Negative page ids, so every doc keeps its own position in the flat list as its id.
const _PAGE_CONTENTS = -1
## A doc reached by link that the index does not hold, kept apart so following one does not
## discard the index it was followed from.
const _PAGE_EXTERNAL = -2

## Sidebar width, and the narrowest page worth showing beside it, in the same units as max_columns.
const _SIDEBAR_COLUMNS = 28
const _MIN_CONTENT_COLUMNS = 60
## Frames a scroll waits, since label heights only settle once the page is laid out at its real width.
const _SCROLL_SETTLE_FRAMES = 2

## History location keys. PATH is only used by external pages.
const _LOC_PAGE = "page"
const _LOC_PATH = "path"
const _LOC_ANCHOR = "anchor"
const _LOC_SCROLL = "scroll"

## Node name of the submenu under Project > Tools. Every packaged copy of this script looks it
## up by this name, so it cannot change.
const _DOCS_MENU_NAME = "Docs"

signal doc_opened(path:String)

## Addon directory, a doc directory, or a single file.
var docs_path:String = "":
	set = set_docs_path
## Optional (lang:String) -> SyntaxHighlighter, handed straight to the markdown view.
var highlighter_provider:Callable:
	set = set_highlighter_provider
## Widest the page gets, in widths of "0" in the theme font (CSS "ch"), so it scales with the editor.
var max_columns:int = 100:
	set = set_max_columns

var _docs:Array = []
var _doc_dir:String = ""
var _current:int = _PAGE_CONTENTS
var _external_path:String = ""

var _back:Array[Dictionary] = []
var _forward:Array[Dictionary] = []
## Still on the contents page reload() opened. The window may not have its real size yet, so the
## first resize wide enough for the sidebar swaps in the first doc instead.
var _landing:bool = false
var _pending_scroll:Dictionary = {}
var _pending_frames:int = 0

var _header:HBoxContainer
var _back_button:Button
var _forward_button:Button
var _title_label:Label
var _contents_button:Button
var _sidebar:ScrollContainer
var _sidebar_rule:VSeparator
var _side_toc:RichTextLabel
var _scroll:ScrollContainer
var _column:ColumnContainer
var _toc:RichTextLabel
var _view:MDView
var _footer:HBoxContainer
var _prev_button:Button
var _next_button:Button


func _init() -> void:
	name = "Docs"
	set_process(false)


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


## Lists the plugin under Project > Tools > Docs. [param path] is anything docs_path takes; the
## addon directory works for both a released plugin and a dev checkout. False outside the editor.
static func register(plugin_name:String, path:String) -> bool:
	var tools = _find_tools_menu()
	if tools == null:
		return false
	_get_docs_menu(tools, true).register_doc(plugin_name, _make_viewer.bind(path))
	return true


static func unregister(plugin_name:String) -> void:
	var tools = _find_tools_menu()
	if tools == null:
		return
	var menu = _get_docs_menu(tools, false)
	if menu != null:
		menu.unregister_doc(plugin_name)


## The Tools popup has no stable name, so it is picked out by the editor handler it is wired to.
static func _find_tools_menu() -> PopupMenu:
	if not Engine.is_editor_hint():
		return null
	for bar in EditorInterface.get_base_control().find_children("*", "MenuBar", true, false):
		for menu in bar.find_children("*", "PopupMenu", true, false):
			for data in menu.get_signal_connection_list(&"index_pressed"):
				if String((data.callable as Callable).get_method()).ends_with("::_tool_menu_option"):
					return menu
	push_warning("DocViewer: could not find the Project > Tools menu.")
	return null


## Untyped on purpose: the node may be another plugin's copy of DocsMenu, so it is only ever
## called by method name.
static func _get_docs_menu(tools:PopupMenu, create:bool) -> Node:
	var menu = tools.get_node_or_null(_DOCS_MENU_NAME)
	if menu != null and menu.has_method(&"register_doc"):
		return menu
	if not create:
		return null
	menu = DocsMenu.new()
	tools.add_submenu_node_item(_DOCS_MENU_NAME, menu)
	return menu


## Handed to the menu as the item's factory, so each tab is built by its own plugin's copy.
static func _make_viewer(path:String) -> Control:
	var viewer = new()
	viewer.docs_path = path
	return viewer


static func _default_parent() -> Node:
	if Engine.is_editor_hint():
		return EditorInterface.get_base_control()
	return null


static func _ui_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0


func _ready() -> void:
	_header = HBoxContainer.new()
	add_child(_header)

	_back_button = _new_header_button(_header, &"Back", "<", "Back (Alt+Left)")
	_back_button.pressed.connect(go_back)
	_forward_button = _new_header_button(_header, &"Forward", ">", "Forward (Alt+Right)")
	_forward_button.pressed.connect(go_forward)
	_contents_button = _new_header_button(_header, &"", "☰ " + CONTENTS_TITLE, "")
	_contents_button.pressed.connect(show_contents)

	_title_label = Label.new()
	_header.add_child(_title_label)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	add_child(HSeparator.new())

	var body = HBoxContainer.new()
	add_child(body)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_sidebar = ScrollContainer.new()
	body.add_child(_sidebar)
	_sidebar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var side_margin = _new_margin()
	_sidebar.add_child(side_margin)
	side_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_toc = _new_toc()
	side_margin.add_child(_side_toc)

	_sidebar_rule = VSeparator.new()
	body.add_child(_sidebar_rule)

	# Full width so its scrollbar stays at the window edge; only the page inside is held narrow.
	_scroll = ScrollContainer.new()
	body.add_child(_scroll)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	_column = ColumnContainer.new()
	_scroll.add_child(_column)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin = _new_margin()
	_column.add_child(margin)

	var page = VBoxContainer.new()
	margin.add_child(page)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_toc = _new_toc()
	page.add_child(_toc)

	_view = MDView.new()
	page.add_child(_view)
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.highlighter_provider = _view_highlighter()
	_view.style_provider = _editor_style
	_view.link_activated.connect(_on_link_activated)

	_footer = HBoxContainer.new()
	add_child(_footer)

	_prev_button = Button.new()
	_footer.add_child(_prev_button)
	_prev_button.focus_mode = Control.FOCUS_NONE
	_prev_button.pressed.connect(func(): _go(_loc(_current - 1)))

	_footer.add_spacer(false)

	_next_button = Button.new()
	_footer.add_child(_next_button)
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.pressed.connect(func(): _go(_loc(_current + 1)))

	_update_metrics()
	reload()


func _new_header_button(parent:Control, icon_name:StringName, text:String, tooltip:String) -> Button:
	var button = Button.new()
	parent.add_child(button)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tooltip
	# Editor icon where there is an editor theme to take one from, the text everywhere else.
	if icon_name != &"" and Engine.is_editor_hint():
		button.icon = EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")
	else:
		button.text = text
	return button


func _view_highlighter() -> Callable:
	return highlighter_provider if highlighter_provider.is_valid() else _default_highlighter


## The built-in highlighter is an editor class, so it is made by name and not always there.
static func _default_highlighter(lang:String) -> SyntaxHighlighter:
	if lang in ["", "gd", "gdscript"] and ClassDB.can_instantiate(&"GDScriptSyntaxHighlighter"):
		return ClassDB.instantiate(&"GDScriptSyntaxHighlighter")
	return null


## Editor theme values for the markdown view; anything missing falls back to its own defaults.
func _editor_style() -> Dictionary:
	var style = {MDView.STYLE_CODE_FONT_COLOR: Color.WHITE}
	var colors = {
		MDView.STYLE_ACCENT: &"accent_color",
		MDView.STYLE_CODE_BG: &"dark_color_2",
		MDView.STYLE_WARNING: &"warning_color",
		MDView.STYLE_ERROR: &"error_color",
	}
	for key in colors:
		if has_theme_color(colors[key], &"Editor"):
			style[key] = get_theme_color(colors[key], &"Editor")
	if has_theme_font(&"source", &"EditorFonts"):
		style[MDView.STYLE_CODE_FONT] = get_theme_font(&"source", &"EditorFonts")
	if Engine.is_editor_hint():
		style[MDView.STYLE_COPY_ICON] = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
	return style


func _new_margin() -> MarginContainer:
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi(8 * _ui_scale()))
	return margin


func _new_toc() -> RichTextLabel:
	var toc = RichTextLabel.new()
	toc.bbcode_enabled = true
	toc.fit_content = true
	toc.selection_enabled = true
	toc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toc.meta_clicked.connect(_on_link_activated)
	return toc


func _notification(what:int) -> void:
	if not is_node_ready():
		return
	match what:
		NOTIFICATION_THEME_CHANGED:
			_update_metrics()
			_update_nav()
		NOTIFICATION_RESIZED:
			if _landing and _docs.size() > 1 and _is_wide():
				_open(_loc(0))
			else:
				_update_nav()


func _process(_delta:float) -> void:
	_pending_frames -= 1
	if _pending_frames > 0:
		return
	set_process(false)
	var anchor:String = _pending_scroll.get(_LOC_ANCHOR, "")
	if anchor == "":
		_scroll.scroll_vertical = _pending_scroll.get(_LOC_SCROLL, 0)
		return
	var heading = _view.anchor_control(anchor)
	if heading != null and heading.is_visible_in_tree():
		_scroll.scroll_vertical += roundi(heading.global_position.y - _scroll.global_position.y)


## Mouse side buttons and Alt+arrows step through history, only while the pointer is over the
## viewer - the script editor binds Alt+arrows too, and the viewer can sit in the main window.
func _input(event:InputEvent) -> void:
	var step := 0
	var mouse = event as InputEventMouseButton
	var key = event as InputEventKey
	if mouse != null and mouse.pressed:
		if mouse.button_index == MOUSE_BUTTON_XBUTTON1:
			step = -1
		elif mouse.button_index == MOUSE_BUTTON_XBUTTON2:
			step = 1
	elif key != null and key.pressed and key.alt_pressed and not (key.shift_pressed or key.ctrl_pressed or key.meta_pressed):
		if key.keycode == KEY_LEFT:
			step = -1
		elif key.keycode == KEY_RIGHT:
			step = 1
	if step == 0 or not is_visible_in_tree() or not get_global_rect().has_point(get_global_mouse_position()):
		return
	if step < 0:
		go_back()
	else:
		go_forward()
	get_viewport().set_input_as_handled()


func set_docs_path(value:String) -> void:
	docs_path = value
	if is_node_ready():
		reload()


func set_highlighter_provider(value:Callable) -> void:
	highlighter_provider = value
	if is_instance_valid(_view):
		_view.highlighter_provider = _view_highlighter()


func set_max_columns(value:int) -> void:
	max_columns = value
	if is_node_ready():
		_update_metrics()


## Shows one file as the whole viewer - no folder scan, no contents page.
func display(path:String) -> void:
	docs_path = path


## Empties the viewer, leaving docs_path as it is.
func clear() -> void:
	_reset()
	if is_node_ready():
		_open(_loc(_PAGE_CONTENTS))


## Rescans the doc folder and returns to whichever page makes sense for what was found.
func reload() -> void:
	# Nothing to draw into yet - _ready calls this again once the controls exist.
	if not is_node_ready():
		return
	_reset()

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

	# The sidebar already lists every doc, so there is no contents page to land on beside it.
	if _docs.size() == 1 or (_docs.size() > 1 and _is_wide()):
		_open(_loc(0))
	else:
		_open(_loc(_PAGE_CONTENTS))
		_landing = _docs.size() > 1


func show_contents() -> void:
	_go(_loc(_PAGE_CONTENTS))


func go_back() -> void:
	if _back.is_empty():
		return
	_forward.append(_here())
	_open(_back.pop_back())


func go_forward() -> void:
	if _forward.is_empty():
		return
	_back.append(_here())
	_open(_forward.pop_back())


func _reset() -> void:
	_docs = []
	_doc_dir = ""
	_current = _PAGE_CONTENTS
	_external_path = ""
	_back.clear()
	_forward.clear()
	_landing = false


## [param anchor] is a heading id to open the page at; without one it opens at [param scroll].
func _loc(page:int, path:String = "", anchor:String = "", scroll:int = 0) -> Dictionary:
	return {_LOC_PAGE: page, _LOC_PATH: path, _LOC_ANCHOR: anchor, _LOC_SCROLL: scroll}


func _here() -> Dictionary:
	return _loc(_current, _external_path, "", _scroll.scroll_vertical)


func _can_open(loc:Dictionary) -> bool:
	var page:int = loc[_LOC_PAGE]
	return page == _PAGE_CONTENTS or page == _PAGE_EXTERNAL or (page >= 0 and page < _docs.size())


## Every navigation the reader makes goes through here, so each one can be stepped back from.
func _go(loc:Dictionary) -> void:
	if not _can_open(loc):
		return
	_back.append(_here())
	_forward.clear()
	_open(loc)


## Shows [param loc] without touching history.
func _open(loc:Dictionary) -> void:
	if not _can_open(loc):
		return
	_landing = false
	var page:int = loc[_LOC_PAGE]
	var path:String = loc[_LOC_PATH]
	# Same page, e.g. an in-page anchor or stepping back from one: scroll it, don't re-render it.
	var same = page != _PAGE_CONTENTS and page == _current and path == _external_path and _view.visible
	_current = page
	_external_path = path

	if page == _PAGE_CONTENTS:
		_view.hide()
		_view.clear()
		_toc.show()
		_toc.text = _build_contents()
		_title_label.text = CONTENTS_TITLE
	elif not same:
		var external = page == _PAGE_EXTERNAL
		var file = path if external else String(_docs[page][DocIndex.KEY_PATH])
		_toc.hide()
		_view.show()
		_view.set_file(file)
		_title_label.text = DocIndex.title_for(file) if external else _docs[page][DocIndex.KEY_TITLE]
		_scroll.scroll_vertical = 0
		doc_opened.emit(file)

	_update_nav()
	_scroll_to(loc[_LOC_ANCHOR], loc[_LOC_SCROLL])


## Scrolls once the page has laid out, to the heading [param anchor] names or else to [param offset].
## A later call replaces a pending one, and an unknown anchor is ignored.
func _scroll_to(anchor:String, offset:int) -> void:
	if anchor == "":
		_scroll.scroll_vertical = offset
	_pending_scroll = {_LOC_ANCHOR: anchor, _LOC_SCROLL: offset}
	_pending_frames = _SCROLL_SETTLE_FRAMES
	set_process(is_inside_tree())


## Contents as one bbcode block: the depth-first order already reads as a tree once each entry is
## indented by its depth, with a bold row wherever the walk enters a new directory.
## [param highlight] is the doc to mark as the current page.
func _build_contents(highlight:int = _PAGE_CONTENTS) -> String:
	if _docs.is_empty():
		return EMPTY_MESSAGE

	var lines:Array[String] = []
	var current_dir:PackedStringArray = []
	for i in range(_docs.size()):
		var doc:Dictionary = _docs[i]
		var segments = String(doc[DocIndex.KEY_REL]).get_base_dir().split("/", false)
		if segments != current_dir:
			var shared := 0
			while shared < segments.size() and shared < current_dir.size() and segments[shared] == current_dir[shared]:
				shared += 1
			for j in range(shared, segments.size()):
				lines.append(_indented("[b]%s[/b]" % segments[j].capitalize(), j))
			current_dir = segments
		var title:String = doc[DocIndex.KEY_TITLE]
		if i == highlight:
			title = "[b]%s[/b]" % title
		var link = "[url=%s]%s[/url]" % [doc[DocIndex.KEY_PATH], title]
		lines.append(_indented(link, doc[DocIndex.KEY_DEPTH]))

	return "\n".join(lines)


## Every [indent] closed on its own line, or the rows after a nested one inherit its depth.
func _indented(text:String, depth:int) -> String:
	if depth <= 0:
		return text
	return "[indent]".repeat(depth) + text + "[/indent]".repeat(depth)


## Width of "0" in the theme font, the unit max_columns and the sidebar are measured in.
func _char_width() -> float:
	var font = get_theme_default_font()
	if font != null:
		var width = font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size()).x
		if width > 0:
			return width
	return 8.0 * _ui_scale()


func _update_metrics() -> void:
	var char_width = _char_width()
	_column.max_width = max_columns * char_width
	_sidebar.custom_minimum_size.x = _SIDEBAR_COLUMNS * char_width
	# The text button outgrows the icon ones, so the row would jump as it shows and hides.
	_header.custom_minimum_size.y = _contents_button.get_combined_minimum_size().y


func _is_wide() -> bool:
	return size.x >= (_SIDEBAR_COLUMNS + _MIN_CONTENT_COLUMNS) * _char_width()


func _update_nav() -> void:
	_back_button.disabled = _back.is_empty()
	_forward_button.disabled = _forward.is_empty()

	# One doc means there is nothing to navigate between and no contents worth showing.
	var multiple = _docs.size() > 1
	# Never beside the contents page, which would list every doc twice.
	var sidebar = multiple and _current != _PAGE_CONTENTS and _is_wide()
	_sidebar.visible = sidebar
	_sidebar_rule.visible = sidebar
	if sidebar:
		var text = _build_contents(_current)
		if _side_toc.text != text: # resizes land here too, and a re-parse is not free
			_side_toc.text = text
	_contents_button.visible = multiple and not sidebar and _current != _PAGE_CONTENTS
	_footer.visible = multiple

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

	var target = meta.get_slice("#", 0)
	var anchor = meta.substr(target.length() + 1)
	if target == "":
		_go(_loc(_current, _external_path, anchor))
		return
	if not target.contains("://") and not target.begins_with("/"):
		target = _current_dir().path_join(target).simplify_path()

	var index = _index_of(target)
	if index != -1:
		_go(_loc(index, "", anchor))
		return

	if not FileAccess.file_exists(target):
		push_warning("DocViewer: unresolved link '%s'" % meta)
		return

	# A doc outside the index still opens, as a page of its own in the history.
	if target.get_extension().to_lower() == "md":
		_go(_loc(_PAGE_EXTERNAL, target, anchor))
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


## Holds its children to [member max_width] (0 for no limit), centered in the width it is given.
class ColumnContainer extends Container:
	var max_width:float = 0.0:
		set(value):
			max_width = value
			queue_sort()

	func _notification(what:int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		var width = size.x if max_width <= 0.0 else minf(size.x, max_width)
		var rect = Rect2(floorf((size.x - width) / 2.0), 0.0, width, size.y)
		for child in get_children():
			if child is Control and child.visible:
				fit_child_in_rect(child, rect)

	func _get_minimum_size() -> Vector2:
		var result = Vector2.ZERO
		for child in get_children():
			if child is Control and child.visible:
				result = result.max(child.get_combined_minimum_size())
		return result


## The Project > Tools > Docs submenu, shared by every plugin that registers. All state sits on
## the node - its items are the registry - so an editor script reload cannot orphan them the way
## it would a static. One window holds every plugin's docs, a tab each.
class DocsMenu extends PopupMenu:
	var _window:Window

	func _init() -> void:
		name = _DOCS_MENU_NAME
		index_pressed.connect(_on_index_pressed)

	## [param factory] takes nothing and returns the Control to show in the plugin's tab.
	func register_doc(plugin_name:String, factory:Callable) -> void:
		_remove_item(plugin_name)
		add_item(plugin_name)
		set_item_metadata(item_count - 1, factory)

	func unregister_doc(plugin_name:String) -> void:
		_remove_item(plugin_name)
		var tabs = _get_tabs()
		if tabs != null and tabs.has_node(plugin_name):
			tabs.get_node(plugin_name).queue_free()
		if item_count > 0:
			return

		if is_instance_valid(_window):
			_window.queue_free()
		var tools = get_parent() as PopupMenu
		if tools != null:
			for i in range(tools.item_count):
				if tools.get_item_submenu_node(i) == self:
					tools.remove_item(i)
					break
			# Removed now, not just queued: a plugin reload registers again in the same frame.
			tools.remove_child(self)
			tools.reset_size()
		queue_free()

	func _remove_item(plugin_name:String) -> void:
		for i in range(item_count):
			if get_item_text(i) == plugin_name:
				remove_item(i)
				return

	func _on_index_pressed(index:int) -> void:
		var plugin_name = get_item_text(index)
		var factory = get_item_metadata(index)
		var tabs = _get_tabs()
		if tabs == null:
			tabs = _open_window()
		var tab = tabs.get_node_or_null(plugin_name)
		if tab == null:
			if not (factory is Callable and factory.is_valid()):
				return
			tab = factory.call()
			tabs.add_child(tab)
			# After add_child: the viewer names itself in _init, and the tab title is the node name.
			tab.name = plugin_name
		tabs.current_tab = tab.get_index()
		_window.grab_focus()

	func _get_tabs() -> TabContainer:
		if not is_instance_valid(_window) or _window.is_queued_for_deletion():
			return null
		return _window.get_child(0)

	func _open_window() -> TabContainer:
		_window = Window.new()
		_window.title = "Documentation"
		_window.close_requested.connect(_window.queue_free)
		var tabs = TabContainer.new()
		_window.add_child(tabs)
		EditorInterface.get_base_control().add_child(_window)
		tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window.popup_centered(_WINDOW_SIZE * EditorInterface.get_editor_scale())
		return tabs
