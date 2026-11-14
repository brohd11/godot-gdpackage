# Setup and exporting

Enable GDPackage in **Project Settings → Plugins**. The GUI is under **Project → Tools → GDPackage**, and commands run in [Editor Console](https://github.com/brohd11/Godot-Editor-Console).

## Initialize a package

```text
gdpackage init plugin my_plugin
gdpackage new_plugin my_plugin
gdpackage init package _lib/my_library
```

- `init plugin` creates the export config for an existing plugin or library folder. Also available from the GUI's tool menu.
- `new_plugin` creates a plugin (`plugin.gd`, `plugin.cfg`) under `addons/` from a template, with its export config.
- `init package` creates a library package: `package.cfg` with a `[package]` section, a Git repository if needed, `src/`, and the export config.

## Configuration and output

Initialization creates the `_export_ignore/` folder:

- `export.yml` - the export config. See [Export settings](export_settings.md).
- `doc/` and `test/` - documentation and development tests.
- `exports/` - default output root. A `.gdignore` keeps Godot from importing the exports, and a `.gitignore` is written for the folder.

The export-ignore folder is never exported, regardless of the exclusion list. `export_ignore/` works as well; when both hold a config, `_export_ignore/` wins.

Pre/post export hooks are optional:

- Create a script extending `GDPackage.ExportScript` and implement `pre_export()` and/or `post_export()`.
- Set `pre_script` and `post_script` to its path in the config.
- Override `_configure(export_data)` to read more export data. Call `super._configure(export_data)` to keep the base `export_path` setup.

## Preview and export

Open the GUI from the tools menu, or with a package selected:

```text
gdpackage open gui my_plugin
```

**Parse** in the tool menu populates the export data. The export tree shows every file, including referenced files outside the package, and labels remote files and their dependencies. **Export** writes the package, or run:

```text
gdpackage export my_plugin
gdpackage open export_dir my_plugin
```

A normal export reads the current working tree, including uncommitted changes. For a verified build from tags, see [Releases](releases.md).

Utility libraries and supporting plugins can be bundled alongside the package's own files:

![Example export tree showing shared libraries and a bundled supporting plugin](https://github.com/user-attachments/assets/d391a7b0-84dc-416e-a221-6a5fa798d9ee)

See [Dependencies and tags](dependencies.md) for gathering and rewriting rules.

## Package targets

Commands that take an existing package accept a path relative to `res://addons/`, a `res://` path, or an absolute filesystem path inside the project:

```text
gdpackage export _lib/my_package # equal to res://addons/_lib/my_package
gdpackage init plugin res://lib/my_package
gdpackage export res://lib/my_package
gdpackage export --release --local res://lib/my_package
```

This applies to `export`, `init plugin`, `init license`, `open`, `ci`, `min_version` and the package-targeted `require` commands. `require consumers` takes a repository identifier instead (ie. owner/repo).

## Package metadata

The package cfg is `plugin.cfg` or `package.cfg` in the folder, checked in that order. Package keys (`version`, `path`, `url`, `require`, etc.) are read key by key from `[package]`, then `[plugin]`. So a `plugin.cfg` can keep them in their own section, or leave everything under `[plugin]`.

See [Commands](commands.md) for syntax and flags, [Testing](testing.md) to set up tests, and [Releases](releases.md) for dependency declarations and release workflows.
