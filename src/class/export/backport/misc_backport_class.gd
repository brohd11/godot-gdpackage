const CompatData = preload("res://addons/gdpackage/src/class/export/backport/compat_data.gd")

const BACKPORTED = 100

static func type_string_compat(type:int):
	return CompatData.VARIANT_TYPES.get(type, "Type not found: %s" % type)

static func has_static_method_compat(method:String, script:Script) -> bool:
	if BACKPORTED >= 4:
		return method in script
	
	var base_script = script
	while base_script != null:
		var method_list = base_script.get_script_method_list()
		for data in method_list:
			var name = data.get("name")
			if name == method:
				return true
		base_script = base_script.get_base_script()
	
	var class_list = ClassDB.get_class_list()
	var script_type = script.get_instance_base_type()
	if script_type in class_list:
		var methods = ClassDB.class_get_method_list(script_type)
		for m in methods:
			var name = m.get("name")
			if name == method:
				return true
	
	return false

static func is_part_of_edited_scene_compat(node_to_check:Node):
	var ed_scene_root:Node = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(ed_scene_root):
		return false
	if ed_scene_root.is_ancestor_of(node_to_check):
		return true
	return false
