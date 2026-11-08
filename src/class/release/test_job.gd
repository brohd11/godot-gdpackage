@tool
extends RefCounted
## What a test CI workspace's autorun loads (ReleaseRunner.TEST_JOB): the package's suites through
## util_r's TestRunner, so CI and the editor console's `test` judge suites the same way.

const TestRunner = preload("uid://bcluoc7e06nvj") #! resolve UtilR.Test.TestRunner
const ExportIgnore = preload("uid://c4pt5djyuf8c") #! resolve GDPackageSpec.ExportIgnore
const TestFiles = preload("res://addons/gdpackage/src/class/export/test_files.gd")


static func run(dir:String) -> Dictionary:
	return await TestRunner.run_files(find_suites(dir))


## Adjacent suites plus the canonical dev test directory, without its fixtures and old exports
## becoming additional roots of the package-wide search.
static func find_suites(package_dir:String) -> Array:
	var search = TestRunner.GetFiles.open(package_dir)
	search.file_extensions = ["gd"]
	search.ignore_dir_names = ExportIgnore.NAMES
	var paths = Array(search.get_files())
	var dev_dir = ExportIgnore.dir_in(package_dir)
	if dev_dir != "":
		paths.append_array(Array(TestRunner.GetFiles.scan(dev_dir.path_join("test"), ["gd"])))
	var classifier = TestFiles.new()
	classifier.index_classes(paths)
	var suites = {}
	for path:String in paths:
		if path.ends_with(TestRunner.SUFFIX) and not classifier.is_framework_test(path):
			suites[path] = true
	var sorted = suites.keys()
	sorted.sort()
	return sorted
