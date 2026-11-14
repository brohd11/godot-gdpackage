# Setup and exporting

Enable GDPackage in **Project Settings → Plugins**. Its GUI is available from
**Project → Tools → GDPackage**, and its commands run in [editor console](https://github.com/brohd11/Godot-Editor-Console).

## Initialize a package

For an existing plugin or library folder, initialize its export configuration:

```text
gdpackage init plugin my_plugin
```

To create an editor plugin from a template, or initialize a folder as a library package:

```text
gdpackage new_plugin my_plugin
gdpackage init package _lib/my_library
```

`new_plugin` creates a plugin (plugin.gd, plugin.cfg) under `addons/` and initializes its export settings.
`init package` creates `package.cfg` with a `[package]` section, initializes a Git
repository if needed, creates `src/`, and initializes the export settings.

You can also initialize an existing folder from the GUI's tool menu.

## Configuration and output

Initialization creates `_export_ignore/export.yml`. The export-ignore folder
is always excluded from the exported package, regardless of the exclusion list.
Initialization also creates `doc/` and `test/` beside the config for documentation
and development tests.

The default output root is `<export-ignore>/exports/`. A `.gdignore` file keeps the
generated exports from being imported into your project. Initialization also writes a
`.gitignore` for `exports/`. See [Export settings](export_settings.md) to change the output or define export variants.

Pre/post export hooks are optional. Create a script extending `GDPackage.ExportScript`,
implement `pre_export()` and/or `post_export()`, and set `pre_script` and `post_script`
to its path in the config. Override `_configure(export_data)` to read more export data;
call `super._configure(export_data)` to retain the base `export_path` setup.

## Preview and export

Open the GUI from the tools menu under Project menu button or with a package selected via command:

```text
gdpackage open gui my_plugin
```

Use **Parse** in the tool menu to populate the export data. You can inspect the export tree,
including referenced files outside the package. The tree labels remote files and their dependencies.
Use **Export** to write the package, or run:

```text
gdpackage export my_plugin
gdpackage open export_dir my_plugin
```

A normal export reads the current working tree, including uncommitted changes.
For a verified build from tags, see [Releases](releases.md).

GDPackage can bundle utility libraries and supporting plugins alongside the package's
own files. This example shows the export tree:

![Example export tree showing shared libraries and a bundled supporting plugin](https://github.com/user-attachments/assets/d391a7b0-84dc-416e-a221-6a5fa798d9ee)

See [Dependencies and tags](dependencies.md) for gathering and rewriting rules.

## Package targets

Existing-package commands accept paths relative to `res://addons/`, explicit `res://`
paths, or absolute filesystem paths inside the current project:

```text
gdpackage export _lib/my_package # equal to res://addons/_lib/my_package
gdpackage init plugin res://lib/my_package
gdpackage export res://lib/my_package
gdpackage export --release --local res://lib/my_package
```

This applies to `export`, `init plugin`, `init license`, `open`, `ci`, package-targeted
`require` commands, and `min_version`. `require consumers` takes a repository identifier (ie. owner/repo).

## Package metadata

A package cfg is the first of `plugin.cfg`, `package.cfg`, in the folder, in that order. Package keys (`version`, `path`, `url`,
`require`, etc.) are read key by key from `[package]`, then `[plugin]`.
So, in a `plugin.cfg` you can separate the data into it's own section, or just leave it all under `[plugin]`.

See [Commands](commands.md) for syntax and flags, [Testing](testing.md) to set up tests,
and [Releases](releases.md) for dependency declarations and release workflows.
