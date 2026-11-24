extends RefCounted

## Hardcoded min-version rules for GDScript *language* features that have no
## presence in extension_api.json (those are dated data-driven via `version_api.gd`).
## Patterns match the string/comment-sanitized line.
## Limitations (not reliably detectable by regex): local constants used as type
## hints (4.2); typed node exports `@export var x: NodeType` (4.2) — needs a type check.
## `@export_storage` (4.3) is UNVERIFIED — no 4.3 binary to confirm against.

const URegex = preload("uid://d0rbf4as6kpns") #! resolve UtilR.Strings.URegex

## Each rule: { name, version, regex:RegEx }, matched against sanitized code.
const _DEFS := [
	# 4.1
	{"name": "static var", "version": "4.1",
		"pattern": "^\\s*static\\s+var\\s+"},
	{"name": "_static_init() static constructor", "version": "4.1",
		"pattern": "^\\s*(static\\s+)?func\\s+_static_init\\b"},
	{"name": "@static_unload", "version": "4.1",
		"pattern": "^\\s*@static_unload\\b"},
	# 4.2
	{"name": "typed for-loop variable", "version": "4.2",
		"pattern": "^\\s*for\\s+[A-Za-z_][A-Za-z0-9_]*\\s*:"},
	# 4.3
	{"name": "is not operator", "version": "4.3",
		"pattern": "\\S+\\s+is\\s+not\\s+\\S+"},
	{"name": "not in operator", "version": "4.3",
		"pattern": "\\bnot\\s+in\\b"},
	{"name": "@export_custom", "version": "4.3",
		"pattern": "^\\s*@export_custom\\b"},
	{"name": "@export_storage", "version": "4.3",  # unverified
		"pattern": "^\\s*@export_storage\\b"},
	# 4.4
	{"name": "@export_tool_button", "version": "4.4",
		"pattern": "^\\s*@export_tool_button\\b"},
	{"name": "typed Dictionary", "version": "4.4",
		"pattern": "\\bDictionary\\s*\\["},
	{"name": "raw string literal", "version": "4.4",
		"pattern": "(?<!\\w)r" + URegex.STRING_PLACEHOLDER_PATTERN},
	# 4.5
	{"name": "@abstract / abstract class", "version": "4.5",
		"pattern": "^\\s*(@abstract\\b|abstract\\s+(class|func)\\b)"},
	{"name": "variadic function arguments", "version": "4.5",
		"pattern": "\\.\\.\\.[A-Za-z_]"},
]

var _rules: Array = []


## Returns [{ name, version, regex:RegEx }, ...], compiled once.
func get_rules() -> Array:
	if not _rules.is_empty():
		return _rules
	for def in _DEFS:
		var re := RegEx.new()
		re.compile(def["pattern"])
		_rules.append({
			"name": def["name"],
			"version": def["version"],
			"regex": re,
		})
	return _rules
