extends "res://addons/_lib/util_r/src/test/test_frameworks.gd"
## Test classification for exports and CI. Framework detection lives in util_r's TestFrameworks,
## so gdpackage and the gdsh `test` command agree on what a framework suite is.


func is_test(path:String) -> bool:
	return path.ends_with(NATIVE_SUFFIX) or is_framework_test(path)
