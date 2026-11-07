extends RefCounted

const TaggedHub = preload("res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_tagged_hub.gd")
const Leaf = TaggedHub.Leaf


static func value() -> int:
	return Leaf.value()
