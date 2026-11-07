extends RefCounted
## Everything else here would pass through this hub, but skipping it would lose the tag below.

const Leaf = preload("res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/lib_leaf.gd")
const NOTE = "res://addons/gdpackage/export_ignore/test/fixtures/vendor/hub/tag_note.txt" #! dependency <package>/src/deps/tag_note.txt
