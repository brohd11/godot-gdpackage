extends RefCounted

## Scans a plugin's source files and reports the minimum Godot version required.
##
## Type resolution is parser-free: `ClassName.member` receivers ARE the class,
## and bare/`self.` calls resolve against the script's own base class via
## `Script.get_instance_base_type()`. Instance access on other variables
## (`node.method()`) needs real type inference and is deferred to a future
## parser-based scan; members missing from the index are assumed user-defined.

const URegex = preload("uid://d0rbf4as6kpns") #! resolve UtilR.Strings.URegex
const VersionApi = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/version_api.gd")
const SyntaxRules = preload("res://addons/gdpackage/src/editor_plugins/console_command/min_version/syntax_rules.gd")

var api := VersionApi.new()
## Off for scripts outside this project (release workspaces): loading them here would parse them
## against this project's classes. The base then comes from a native `extends` line only.
var load_scripts := true

var _syntax := SyntaxRules.new()

var _string_regex: RegEx
var _scoped_regex: RegEx        # Class.member (static access)
var _bare_call_regex: RegEx     # foo(  -> global utility or base-class method
var _self_regex: RegEx          # self.member -> base-class member
var _class_token_regex: RegEx   # bare PascalCase token (class existence)
var _enum_value_regex: RegEx    # bare ALL_CAPS token -> possible global enum value
var _res_type_regex: RegEx      # type="ClassName" in tscn/tres
var _extends_regex: RegEx       # extends Native (no-load base)


func _init() -> void:
	_string_regex = URegex.get_strings()
	_scoped_regex = _re("\\b([A-Z][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)\\b")
	_bare_call_regex = _re("(?<![.\\w])([a-z_][A-Za-z0-9_]*)\\s*\\(")
	_self_regex = _re("\\bself\\.([A-Za-z_][A-Za-z0-9_]*)\\b")
	_class_token_regex = _re("\\b([A-Z][A-Za-z0-9_]*)\\b")
	_enum_value_regex = _re("(?<![.\\w])([A-Z][A-Z0-9_]+)\\b")
	_res_type_regex = _re("type=\"([A-Za-z_][A-Za-z0-9_]*)\"")
	_extends_regex = _re("(?m)^extends\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(#.*)?$")


static func _re(pattern: String) -> RegEx:
	var re:RegEx = RegEx.new()
	re.compile(pattern)
	return re


## Scan a set of files. Returns { min_version:String, findings:[{feature,version,location}] },
## location being "path:line". Shared by the min_version command and export's plugin.cfg write.
func scan_files(file_paths: Array) -> Dictionary:
	var min_version: String = api.baseline
	var findings := []
	for file_path: String in file_paths:
		var r := scan_file(file_path)
		min_version = VersionApi.max_version(min_version, r["min_version"])
		for fnd in r["findings"]:
			findings.append({
				"feature": fnd["feature"], "version": fnd["version"],
				"location": "%s:%d" % [file_path, fnd["line"]],
			})
	return {"min_version": min_version, "findings": findings}


## Scan one file. Returns { min_version:String, findings:[{line,feature,version}] }.
func scan_file(file_path: String) -> Dictionary:
	var result := {"min_version": api.baseline, "findings": [], "_seen": {}}
	var ext := file_path.get_extension()
	if ext != "gd" and ext != "tscn" and ext != "tres":
		result.erase("_seen")
		return result

	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		result.erase("_seen")
		return result

	# For .gd, resolve the script's native base class so bare/self calls can be
	# dated against it. "" means unresolved -> bare-call dating is skipped.
	var base := ""
	if ext == "gd":
		base = _resolve_base_type(file_path)

	var line_no := 0
	while not f.eof_reached():
		line_no += 1
		var line := f.get_line()
		if ext == "gd":
			_scan_gd_line(line, line_no, result, base)
		else:
			_scan_resource_line(line, line_no, result)
	f.close()

	result.erase("_seen")
	return result


## Native base type of a .gd script via Script.get_instance_base_type(); "" if it
## can't be loaded as a script.
func _resolve_base_type(file_path: String) -> String:
	if not load_scripts:
		var m := _extends_regex.search(FileAccess.get_file_as_string(file_path))
		return m.get_string(1) if m and api.has_class(m.get_string(1)) else ""
	var res = load(file_path)
	if res is Script:
		return res.get_instance_base_type()
	return ""


func _scan_gd_line(line: String, line_no: int, result: Dictionary, base: String) -> void:
	var stripped := line.strip_edges()
	if stripped == "" or stripped.begins_with("#"):
		return

	# Lambdas capture locals by value, so use a by-reference Array holder to
	# get the sanitized string back out.
	var holder := [""]
	URegex.string_safe_regex_read(line, func(c): holder[0] = c, _string_regex)
	var sanitized: String = holder[0]

	for rule in _syntax.get_rules():
		if (rule["regex"] as RegEx).search(sanitized) != null:
			_record(result, line_no, rule["name"], rule["version"])

	for m in _scoped_regex.search_all(sanitized):
		var cls := m.get_string(1)
		var member := m.get_string(2)
		if api.has_class(cls):
			_record(result, line_no, "%s.%s" % [cls, member], api.member_min_version(cls, member))

	for m in _bare_call_regex.search_all(sanitized):
		var name := m.get_string(1)
		if api.is_global_utility(name):
			_record(result, line_no, "%s()" % name, api.utility_min_version(name))
		elif base != "":
			_record(result, line_no, "%s.%s" % [base, name], api.member_min_version(base, name))

	if base != "":
		for m in _self_regex.search_all(sanitized):
			var member := m.get_string(1)
			_record(result, line_no, "%s.%s" % [base, member], api.member_min_version(base, member))

	for m in _enum_value_regex.search_all(sanitized):
		var name := m.get_string(1)
		var ver := api.global_enum_min_version(name)
		if ver != "":
			_record(result, line_no, name, ver)

	for m in _class_token_regex.search_all(sanitized):
		var cls := m.get_string(1)
		if api.has_class(cls):
			_record(result, line_no, "class %s" % cls, api.class_min_version(cls))


func _scan_resource_line(line: String, line_no: int, result: Dictionary) -> void:
	for m in _res_type_regex.search_all(line):
		var cls := m.get_string(1)
		if api.has_class(cls):
			_record(result, line_no, "resource %s" % cls, api.class_min_version(cls))


## Fold one (feature, version) hit into the result. "" is ignored (unknown /
## user-defined), the baseline version (no floor) is dropped, anything higher
## raises it. Deduped by feature+line so verbose can list every distinct
## occurrence while a feature matched twice on one line collapses.
func _record(result: Dictionary, line_no: int, feature: String, version: String) -> void:
	if version == "" or VersionApi.version_code(version) <= VersionApi.version_code(api.baseline):
		return
	var seen: Dictionary = result["_seen"]
	var key := "%s@%d" % [feature, line_no]
	if seen.has(key):
		return
	seen[key] = true
	result["findings"].append({"line": line_no, "feature": feature, "version": version})
	result["min_version"] = VersionApi.max_version(result["min_version"], version)
