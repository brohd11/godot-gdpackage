extends RefCounted

const Leaf = preload("res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_leaf.gd")
const KeptExtra = preload("res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_kept_extra.gd")


static func ping() -> int:
	return 1
