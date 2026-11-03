extends VBoxContainer

const UtilsRemote = preload("res://addons/gdpackage/src/class/utils_remote.gd")
const Options = UtilsRemote.Options
const UControl = UtilsRemote.UControl
const Confirmation = UtilsRemote.Confirmation

const JSONHighlighter = UtilsRemote.JSONHighlighter
const YAMLHighlighter = UtilsRemote.YAMLHighlighter


const SAVE_COMMANDS = ["Ctrl+S", "Command+S"]

# could just add a floating save button top right
var tool_bar:HBoxContainer


var code_edit:CodeEdit

var current_path:String

func _init() -> void:
	name = "Export Data"

func _ready() -> void:
	tool_bar = HBoxContainer.new()
	add_child(tool_bar)
	
	code_edit = CodeEdit.new()
	add_child(code_edit)
	code_edit.gui_input.connect(_on_ce_gui_input)
	UControl.expand(code_edit)
	#code_edit.code_completion_enabled = true # unsure about this
	code_edit.indent_use_spaces = true
	code_edit.indent_size = 2
	
	

func load_file(path:String):
	if FileAccess.file_exists(path):
		HLWrapper.setup_for_file(code_edit, path)
		code_edit.text = FileAccess.get_file_as_string(path)
		current_path = path
	else:
		code_edit.text = "Could not load:\n" + path

func _on_ce_gui_input(input_event:InputEvent):
	if input_event is InputEventKey and input_event.pressed:
		#print(input_event.as_text_keycode())
		
		if input_event.as_text_keycode() in SAVE_COMMANDS:
			_save_file()
			accept_event()

func _save_file():
	var conf = await Confirmation.confirm("Save file?")
	if not conf:
		return false
	print("GONAN SAVE")
	# confirm?
	pass

func get_options() -> Options:
	var options = Options.new()
	return options



class HLWrapper extends SyntaxHighlighter:
	
	var highlighter
	
	static func setup_for_file(p_code_edit:CodeEdit, file_path:String) -> void:
		var ins = new()
		var json = file_path.get_extension() == "json"
		if json:
			ins.highlighter = JSONHighlighter.new()
		else:
			ins.highlighter = YAMLHighlighter.new()
		
		p_code_edit.draw_tabs = json
		p_code_edit.draw_spaces = not json
		p_code_edit.syntax_highlighter = ins
		
		ins.highlighter.setup(p_code_edit, YAMLHighlighter.Palette.new())
	
	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		return highlighter.get_line_highlighting(line)
