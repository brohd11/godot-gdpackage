# Export settings

Exports are configured in `export.yml`, in the package's export-ignore folder. See [Setup](setup.md#configuration-and-output) for the folder layout and [Commands](commands.md) for export commands.

## Main Settings

- `export_root` - root of the export. Local or global path, inside or outside the project.
- `plugin_folder` - appended to `export_root`. Uses the plugin version by default, so every version's export can sit in this folder.
- `pre_script` / `post_script` - optional scripts whose `pre_export()` / `post_export()` run before and after the export. `""` skips. See [Setup](setup.md#configuration-and-output).
- `exports` - array of export dictionaries.
- `options` - dictionary of options.
- `build_require` - dependencies available during a release build. Defaults to `"@require"`.
- `compile_require` - dependencies also installed beside the export for verification. Defaults to `[]`.
- `test_require` - test dependencies for the package's CI run. Defaults to `"@require"`.
- `exported_require` - dependencies written into the exported cfg's `require=` for installers. Defaults to `[]`.
- `external` - packages the plugin uses but does not bundle. See [External packages](#external-packages). Defaults to `[]`.
- `test` - optional custom runner configuration. See [Testing](testing.md#gut-gdunit4-and-custom-runners).

Requirement keys accept a spec or a list of specs. See [Releases](releases.md#build-requirements) for `"@require"` and dependency kinds.

### exports

- `source` - source location of the plugin.
- `exclude` - optional. Directories, file extensions, and files to ignore on export. The export-ignore folder is always skipped, so it never needs listing.
- `vendor_dir` - where files from outside the plugin are recreated (bundled copies, mirroring their `res://` path). Defaults to `vendor`. `remote_dir`, its old name, is still read. With `ignore_src`, a vendor dir outside `src/` gets its own `.gdignore`.
- `export_name` - package folder under `export_root` + `plugin_folder`, zipped as a whole. Defaults to the last segment of `plugin_folder`.
- `export_folder` - install path relative to `res://`, e.g. `addons/_lib/my_lib`. Recreated inside the package, so it extracts straight into a project. Defaults to `source`; a different path renames the plugin and rewrites its paths to match. No `{{version}}` templates.
- `other_transfers` - other files to transfer into the plugin on export. Two sources resolving to the same destination abort the export. Each entry:
  - `to` - destination, relative to `source` unless it already starts with it. A file for a single-file `from`, a directory otherwise.
  - `from` - a file, an array of files, or a directory. Omit it with a `to` ending in `.gdignore` to write an empty one.
  - `recursive` - bool, defaults false. For a directory `from`, includes subdirectories, keeping their structure under `to`.
  - `ignore_deps` - bool, defaults false. Files are copied and their paths rewritten, but never scanned for dependencies or global classes. For optional integrations that name classes from plugins that may be absent: ship them under a `.gdignore` so they don't compile until loaded.
  - `custom_tree_message` - text appended to the file in the export tree view.
- `external` - more external entries for this export only, added to the top-level list.
- `ignore_dependencies` - do not export any dependencies for the files. All or nothing; use `external` to leave out particular packages. Also accepted under `options`.
- `parser_overide_settings` - optional per-export override of `parser_settings`, same structure.

### External packages

`external` lists packages the export references but leaves out, so they become hard dependencies installed beside the plugin. Each entry is a require spec or a `res://` directory:

```yaml
external:
  - "brohd11/godot-code-completions/release@v0.3.0"
  - "res://addons/some_local_thing"
```

- List a spec here only. Release and test builds install it for the export and beside it for the compile check, as if it were in `compile_require`. A `/release` spec fits best, since nothing from the dependency is bundled.
- If the package cfg's `require` also lists the repo, use the same kind in both places. Asking for the source and the `/release` form of one repo is an error.
- A spec is matched to a local package: in a release workspace by its install path, otherwise by a cfg `url=` naming the repo, then a checkout whose git origin does. An unmatched spec fails the export.
- A spec is added to the exported cfg's `require=` as written. A directory is not; the export warns when no require list names it.
- Files inside an external package are never crawled or copied, and its global classes are not renamed or preloaded, so `extends EditorCodeCompletion` stays as written.
- A path reference into an external package is rewritten to its `uid://`, because that package's own release may move files (`global/`, a hidden `src/`). A file without a UID keeps its path, with a warning for scripts and resources. Prefer global class names or UIDs for these references.

### options

- `include_import` - bool, defaults true. Includes import sidecars.
- `include_uid` - bool, defaults true. Includes UID sidecars.
- `ignore_tests` - bool, defaults true. Leaves `*_test.gd` and GUT/GDUnit4 test scripts out of the export. See [Testing](testing.md#excluding-tests-from-exports).
- `overwrite` - bool. Erases the contents of `export_root` + `plugin_folder` before export. If false, the export aborts when any file already exists.
- `include_docs` - bool, defaults true. Copies the `doc/` folder beside this config into the exported plugin as `.doc`. See [Shipping documentation](shipping_docs.md).
- `include_project_license` - bool, defaults false. Each copied file is matched to the closest LICENSE above it, so a nested library keeps its own. `res://LICENSE` is held out of that matching, since it would claim every file no other license covers. Turn this on for a plugin with no LICENSE of its own that takes the project's; it ships at the export root. Ignored when the plugin has one.
- `use_tag_in_cfg` - bool. Uses Git describe to set the exported cfg version. New configs set it true; an omitted key is false.
- `include_min_version` - bool, defaults true. Writes the scanned minimum Godot version into the exported cfg when the API index is available.
- `toolchain` - released GDPackage version used for isolated builds. Defaults to the development GDPackage version. See [Toolchains](releases.md#toolchain-and-lock-file).
- `parser_settings` - dictionary of settings for the file parsers. Applied to all exports unless overridden.

#### parser_settings

Passed to the file parsers. General keys sit beside the `parse_*` blocks, apply to every parser, and take precedence over the same key inside a block.

##### general - applies to all extensions

- `use_relative_paths` - uses paths relative to the current file for preloads and other script-relative references. Literal runtime `load()` paths stay absolute, because Godot resolves them from the project root.

##### parse_gd

- `class_rename_ignore` - array of class names to leave global instead of stripping and preloading.
- `reduce_access_paths` - bool, default true. Rewrites dotted const chains to direct preloads, so a script ships with what it needs and not the container it went through.
  - `ALibRuntime.Utils.UFile` becomes `Utils_UFile`, with `const Utils_UFile = preload("...")` added unless the script already has a const for that file.
  - A const that is a single literal with no type hint is inlined: `const MY_INT = GlobalClass.MY_INT` becomes `const MY_INT = 3`.
  - Chains are followed through aliases (`const UFile = UtilsRemote.UFile`) and stop at the deepest segment that names a script file, so a trailing inner class or enum is kept: `A.B.UProfile.TimeFunction` -> `B_UProfile.TimeFunction`.
  - A hub outside the source is skipped when every mention of it reduces. One bare use or method call keeps it, as does a subclass or another file still reaching through it.
  - A hub inside the plugin's source ships whole regardless, so a local const pointing at one is left as written.
  - A file containing a `#! gdp-dependency` tag, or one a chain crosses, is never skipped. A const line carrying the tag is never removed.
  - Dynamic reads (`get("UtilsRemote")`, `get_script_constant_map()`) cannot be seen. Put `#! gdp-ignore` on the declaration to keep it, or set this to false.

##### parse_cs

- `namespace_rename` - dictionary with keys "namespace":"rename_as".

### GDScript optimizer

`init plugin` writes this block into each new `export.yml`, with optimization disabled:

```yaml
options:
  parser_settings:
    parse_gd:
      optimizer:
        enabled: false
        struct_mode: tagged # auto | tagged | off
        inline_mode: tagged # auto | tagged | off
        aggressive: false
        debug_tags: false
```

- A config that omits the block or its `enabled` key has the optimizer enabled. Other omitted keys take the defaults above.
- `enabled: false` bypasses the whole optimizer, including validation of the other optimizer keys. Packaging and path relocation still run.
- When enabled, an invalid optimizer key or value invalidates the export before files are copied.
- `struct_mode` and `inline_mode` select tagged definitions, discover eligible ones automatically, or turn the pass off.
- `aggressive` admits reference/Variant types and relaxes inline conversions and lifetimes. Struct usage checks remain.

See [Optimization](optimization.md) for what the passes do.
