extends VBoxContainer
## Renders one parsed markdown doc as a flow of controls - RichTextLabel for prose, headings and
## tables, read-only CodeEdit for fences, TextureRect for standalone images, a panel for quotes.
##
## Every size and color comes from the theme rather than a constant, and the doc re-renders on
## a theme change, so the view tracks the editor's font, scale and accent instead of fighting
## them. Engine-only and host-agnostic: links are reported, never resolved here.

const Parser = preload("res://addons/gdpackage/src/components/doc_viewer/markdown_parser.gd")

const _FALLBACK_FONT_SIZE = 16
## Images are held to a fraction of the viewport height so a screenshot cannot fill the page.
## Width needs no ratio - an image is never allowed past the width of the view itself.
const _MAX_IMAGE_HEIGHT_RATIO = 0.6
## Stand-ins for the editor theme's colors when the view runs somewhere without one.
const _FALLBACK_ACCENT = Color(0.44, 0.73, 0.98)
const _FALLBACK_WARNING = Color(1.0, 0.87, 0.4)
const _FALLBACK_ERROR = Color(1.0, 0.47, 0.42)

signal link_activated(meta:String)

## Optional (lang:String) -> SyntaxHighlighter. Without it, gdscript fences use the built-in
## highlighter and everything else renders plain, which keeps this view dependency free.
var highlighter_provider:Callable

## Directory relative image paths resolve against.
var base_dir:String = ""

var _source:String = ""
var _prose_style:StyleBoxEmpty
var _rendering:bool = false
var _base_size:int = _FALLBACK_FONT_SIZE
## Colors of the current render: accent, code_bg, border, stripe, warning, error.
var _palette:Dictionary = {}
## Parser context of the current render - colors as BBCode values, plus the doc's link refs.
var _ctx:Dictionary = {}
## Heading id -> its control, for anchor links.
var _anchors:Dictionary = {}
var _images:Array[TextureRect] = []


func _init() -> void:
	_prose_style = StyleBoxEmpty.new()


func _notification(what:int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready() and _source != "":
		_render()
	elif what == NOTIFICATION_RESIZED:
		_fit_images()


func set_markdown(text:String) -> void:
	_source = text
	_render()


func set_file(path:String) -> void:
	base_dir = path.get_base_dir()
	set_markdown(FileAccess.get_file_as_string(path))


func clear() -> void:
	_source = ""
	_clear_children()


## The heading control an anchor names, or null. Takes the fragment as it was written in a link.
func anchor_control(id:String) -> Control:
	var control = _anchors.get(id.uri_decode().to_lower())
	return control if is_instance_valid(control) else null


func _clear_children() -> void:
	_anchors.clear()
	_images.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _render() -> void:
	# clear() re-emits theme changes as children leave, which would land back here.
	if _rendering:
		return
	_rendering = true
	_clear_children()

	_base_size = _base_font_size()
	_palette = _resolve_palette()
	_ctx = {
		Parser.CTX_CODE_BG: _bbcode_color(_palette.code_bg),
		Parser.CTX_LINK: _bbcode_color(_palette.accent),
		Parser.CTX_REFS: Parser.link_refs(_source),
	}
	add_theme_constant_override("separation", _separation())
	_render_blocks(Parser.parse(_source), self)
	_rendering = false


func _render_blocks(blocks:Array, parent:Control) -> void:
	for block in blocks:
		match block.get(Parser.KEY_TYPE):
			Parser.TYPE_TEXT:
				parent.add_child(_new_prose(block[Parser.KEY_TEXT]))
			Parser.TYPE_HEADING:
				parent.add_child(_new_heading(block, parent.get_child_count() == 0))
			Parser.TYPE_CODE:
				parent.add_child(_new_code(block[Parser.KEY_TEXT], block[Parser.KEY_LANG]))
			Parser.TYPE_TABLE:
				parent.add_child(_new_table(block))
			Parser.TYPE_QUOTE:
				parent.add_child(_new_quote(block))
			Parser.TYPE_IMAGE:
				parent.add_child(_new_image(block[Parser.KEY_SRC], block[Parser.KEY_ALT]))
			Parser.TYPE_RULE:
				parent.add_child(_new_rule(_palette.border))


## The theme's own size, so headings scale with the editor instead of a hardcoded pixel size.
func _base_font_size() -> int:
	var size = get_theme_default_font_size()
	return size if size > 0 else _FALLBACK_FONT_SIZE


func _separation() -> int:
	return maxi(4, _base_size / 2)


## Editor theme colors where there is an editor theme, tints of the font color everywhere else -
## those read on a light theme as well as a dark one.
func _resolve_palette() -> Dictionary:
	var font = get_theme_color(&"default_color", &"RichTextLabel")
	var accent = _editor_color(&"accent_color", _FALLBACK_ACCENT)
	return {
		"accent": accent,
		"code_bg": _editor_color(&"dark_color_2", Color(font, 0.12)),
		"border": Color(font, 0.2),
		"stripe": Color(font, 0.04),
		"warning": _editor_color(&"warning_color", _FALLBACK_WARNING),
		"error": _editor_color(&"error_color", _FALLBACK_ERROR),
	}


func _editor_color(color_name:StringName, fallback:Color) -> Color:
	if has_theme_color(color_name, &"Editor"):
		return get_theme_color(color_name, &"Editor")
	return fallback


static func _bbcode_color(color:Color) -> String:
	return "#" + color.to_html()


func _new_label() -> RichTextLabel:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.selection_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_stylebox_override("normal", _prose_style)
	# The editor theme's RichTextLabel mono font is not its code font; inline code should match fences.
	if has_theme_font(&"source", &"EditorFonts"):
		label.add_theme_font_override(&"mono_font", get_theme_font(&"source", &"EditorFonts"))
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _new_prose(text:String) -> RichTextLabel:
	var label = _new_label()
	label.text = Parser.to_bbcode(text, _base_size, _ctx)
	return label


## A heading is its own control so an anchor link has something to scroll to. The top two
## levels carry a rule, and every heading but the first stands off from what precedes it.
func _new_heading(block:Dictionary, first:bool) -> Control:
	var level:int = block[Parser.KEY_LEVEL]
	var label = _new_label()
	label.text = Parser.heading_bbcode(block[Parser.KEY_TEXT], level, _base_size, _ctx)
	_anchors[block[Parser.KEY_ID]] = label
	if first and level > 2:
		return label

	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", maxi(2, _base_size / 4))
	if not first:
		var spacer = Control.new()
		spacer.custom_minimum_size.y = _base_size * 0.5
		box.add_child(spacer)
	box.add_child(label)
	if level <= 2:
		box.add_child(_new_rule(Color(_palette.accent, 0.5)))
	return box


func _new_rule(color:Color) -> Control:
	var rule = ColorRect.new()
	rule.color = color
	rule.custom_minimum_size.y = maxi(1, roundi(_base_size / 12.0))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## Built through the table API rather than BBCode cell options, which are newer than the oldest
## engine this script ships to.
func _new_table(block:Dictionary) -> RichTextLabel:
	var label = _new_label()
	var align:Array = block[Parser.KEY_ALIGN]
	var header_bg = Color(_palette.accent, 0.18)
	var padding = Rect2(_base_size * 0.6, _base_size * 0.25, _base_size * 0.6, _base_size * 0.25)

	label.push_table(align.size())
	var rows:Array = [block[Parser.KEY_HEADER]] + block[Parser.KEY_ROWS]
	for row_index in range(rows.size()):
		for column in range(align.size()):
			label.push_cell()
			label.set_cell_padding(padding)
			label.set_cell_border_color(_palette.border)
			if row_index == 0:
				label.set_cell_row_background_color(header_bg, header_bg)
			else:
				label.set_cell_row_background_color(_palette.stripe, Color.TRANSPARENT)
			label.push_paragraph(_cell_alignment(align[column]))
			var cell = Parser.inline_bbcode(rows[row_index][column], _ctx)
			label.append_text("[b]%s[/b]" % cell if row_index == 0 else cell)
			label.pop()
			label.pop()
	label.pop()
	return label


func _cell_alignment(align:String) -> HorizontalAlignment:
	match align:
		Parser.ALIGN_CENTER:
			return HORIZONTAL_ALIGNMENT_CENTER
		Parser.ALIGN_RIGHT:
			return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_LEFT


## A bar down the left edge in the accent color, or the alert's own color, with the quoted
## blocks rendered inside it like any others.
func _new_quote(block:Dictionary) -> Control:
	var kind:String = block[Parser.KEY_KIND]
	var color:Color = _palette.accent
	if kind == "warning":
		color = _palette.warning
	elif kind == "caution":
		color = _palette.error

	var style = StyleBoxFlat.new()
	style.bg_color = Color(color, 0.08)
	style.border_color = color
	style.border_width_left = maxi(2, _base_size / 5)
	style.content_margin_left = _base_size
	style.content_margin_right = _base_size * 0.75
	style.content_margin_top = _base_size * 0.5
	style.content_margin_bottom = _base_size * 0.5

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style)
	var box = VBoxContainer.new()
	panel.add_child(box)
	box.add_theme_constant_override("separation", _separation())

	if kind != "":
		var title = _new_label()
		title.text = "[color=%s][b]%s[/b][/color]" % [_bbcode_color(color), kind.capitalize()]
		box.add_child(title)
	_render_blocks(block[Parser.KEY_BLOCKS], box)
	return panel


func _new_code(text:String, lang:String) -> Control:
	var wrapper = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var code_edit = CodeEdit.new()
	wrapper.add_child(code_edit)
	code_edit.text = text
	code_edit.editable = false
	code_edit.focus_mode = Control.FOCUS_CLICK
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_edit.scroll_fit_content_height = true
	code_edit.context_menu_enabled = false
	# Theme lookups only resolve once the node is in the tree, so the readonly dim is undone there.
	code_edit.ready.connect(_undim_readonly.bind(code_edit))
	var highlighter = _get_highlighter(lang)
	if highlighter != null:
		code_edit.syntax_highlighter = highlighter

	var copy_button = Button.new()
	code_edit.add_child(copy_button)
	# Editor icon where there is an editor theme to take one from, a label everywhere else.
	if Engine.is_editor_hint():
		copy_button.icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
	else:
		copy_button.text = "Copy"
	copy_button.theme_type_variation = &"FlatButton"
	copy_button.flat = true
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.set_anchors_and_offsets_preset.call_deferred(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	copy_button.pressed.connect(DisplayServer.clipboard_set.bind(text))

	return wrapper


func _undim_readonly(code_edit:CodeEdit) -> void:
	code_edit.add_theme_color_override(&"font_readonly_color", code_edit.get_theme_color(&"font_color"))


func _get_highlighter(lang:String):
	if highlighter_provider.is_valid():
		return highlighter_provider.call(lang)
	# The built-in highlighter is an editor class, so it is not always there to instantiate.
	if lang in ["", "gd", "gdscript"] and ClassDB.can_instantiate("GDScriptSyntaxHighlighter"):
		return GDScriptSyntaxHighlighter.new()
	return null


func _new_image(src:String, alt:String) -> Control:
	var path = src
	if not path.contains("://") and base_dir != "":
		path = base_dir.path_join(path).simplify_path()

	var texture = _load_texture(path)
	if texture == null:
		var label = Label.new()
		label.text = alt if alt != "" else src
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return label

	var rect = TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rect.tooltip_text = alt
	# Natural size for now; the first real layout fits it to the width actually available.
	rect.custom_minimum_size = Vector2(texture.get_size())
	_images.append(rect)
	return rect


## Imported images go through the loader - reading one off disk instead works but warns that it
## will not survive an export. Docs shipped in a dot-prefixed folder are never imported, and raw
## file data is the only way to reach those.
func _load_texture(path:String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource
	var image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Images are sized on layout, not on build - at build time the view has no width yet, and a
## window that has not been popped up reports a placeholder size that shrinks every image to it.
func _fit_images() -> void:
	for rect in _images:
		if is_instance_valid(rect):
			_fit_image(rect)


func _fit_image(rect:TextureRect) -> void:
	if rect.texture == null:
		return
	var natural = Vector2(rect.texture.get_size())
	if natural.x <= 0 or natural.y <= 0:
		return

	# An image inside a quote has the quote's width to fit, not the view's.
	var available = (rect.get_parent() as Control).size.x if rect.get_parent() is Control else size.x
	var factor := 1.0
	if available > 0:
		factor = minf(factor, available / natural.x)
	var max_height = get_viewport_rect().size.y * _MAX_IMAGE_HEIGHT_RATIO
	if max_height > 0:
		factor = minf(factor, max_height / natural.y)
	# custom_minimum_size ignores an unchanged value, so this cannot feed itself another resize.
	rect.custom_minimum_size = natural * minf(factor, 1.0)


func _on_meta_clicked(meta:Variant) -> void:
	link_activated.emit(str(meta))
