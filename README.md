# GDPackage

GDPackage authors, tests and releases Godot packages (plugins and libraries);
[gdaddon](https://github.com/brohd11/gdaddon) installs them. Formerly Package Exporter
(`godot-package-exporter`), renamed in 0.11.0.

This plugin is used to create release packages for your plugins.

[Youtube Walkthrough](https://youtu.be/G0ZlF8FJ94U)

The main feature is to get any global classes used in your plugin and remove the class_name, then declare said class in any script that uses it, as a preload. This allows you to work in your development repo with global class names for convenience, but distribute the plugin with only the classes the user will use in the global space. Classes to preload can be [customized](./export_ignore/doc/export_settings.md).

The other aspect of this is that the global class can be outside of the plugin. It would then be copied into your plugin on export. This allows you to keep shared classes in a central folder/submodule, but use the classes as normal.

In the image below, you can see how the exporter itself is exported. The main logic lives in the gdpackage folder, it pulls utility classes from _lib folder, and then pulls the editor_console plugin as a sub plugin.


<img width="1161" height="955" alt="exporter-example-git" src="https://github.com/user-attachments/assets/d391a7b0-84dc-416e-a221-6a5fa798d9ee" />


This will also work with preloaded classes if you want to limit global classes in your dev repo. See [here](./export_ignore/doc/advanced_usage.md) for more details.

All global class or "#! remote" files will be scanned, and any global classes used, preload/loaded files used within will be copied as well, and then scanned recursively.

**Note**: on export a new copy of the files is created. Any plugins using the same classes will technically be a different class. If the classes are not self contained, meaning multiple plugins would need to interact with the same instance of the class, you must account for this.

### Setup

You can open a package exporter instance from the project menu. In the instance tool menu (screwdriver and wrench), select "Plugin Init". This will prompt you to select your plugin folder. Once selected, an "_export_ignore" folder will be created in your plugin (an existing "export_ignore" folder is reused instead - both names work, and "_export_ignore" wins if a plugin has both). It holds an `export.yml` configuration file, as well as a gdscript file that has a pre and post export function. These will be called during export and can be used to do anything that may need to be done before or after export.  For example, resetting config files to default values or creating a .gdignore file manually.

The default export location is "_export_ignore/exports". The folder itself is never copied into an export, whatever the exclude list says. A .gdignore file is created in "exports" so that the files are not imported into your project.

Alternatively, you can run this setup from the [editor console plugin](https://github.com/brohd11/Godot-Editor-Console) that is bundled with this plugin. With or without the GUI open, run: `gdpackage init plugin my_plugin_folder`

With the setup complete, you can click "Read" in the GUI tool menu. This will create a tree that displays all the files that will be exported including the files outside of the plugin. These will be labeled with the file's relationship to the plugin.
 - remote file - global class or "#! remote" files
 - dependency - file found in a remote file when scanned

Console command: `gdpackage open gui my_plugin_folder` will open a GUI instance and read the export file.

### Export

You can export through the GUI by clicking "Export" in the tool menu.

Console command: `gdpackage export my_plugin_folder`


### Package targets

Existing-package commands (`export`, `init plugin`, `init license`, `open gui`, `open export_dir`,
`ci ...`, `require ...` and `min_version`) accept paths relative to `res://addons/`,
explicit `res://` paths, or absolute filesystem paths inside the current project.
For example:

```text
gdpackage export _lib/brohd
gdpackage init plugin res://lib/my_package
gdpackage export res://lib/my_package
gdpackage export --release --local res://lib/my_package
```

Autocomplete recursively finds folders under `addons/` containing a package cfg, suggesting
their addon-relative paths. Export commands suggest configured packages; init suggests packages
without an export config. Packages elsewhere can be addressed explicitly. `new_plugin` continues
to scaffold editor plugins under `addons/`.

A package cfg is the first of `plugin.cfg` or `package.cfg` (then legacy `addon.cfg`, `version.cfg`)
in the folder, the same order gdaddon uses. Package keys (`version`, `path`, `url`, `require`, ...)
are read key by key from `[package]`, then legacy `[addon]`, then `[plugin]`, so a `plugin.cfg` keeps
Godot's own keys beside them. `init package <folder>` writes `package.cfg` with a `[package]`
section; `--name=plugin` picks `plugin.cfg`.

New configs use `export.yml`. Legacy `plugin_export.yml`, `plugin_export.yaml`, and
`plugin_export.json` still work. `_export_ignore` takes precedence over `export_ignore`;
within either folder, `export.yml` takes precedence over legacy filenames.

### GDScript optimization

Exports use the shared GDScript optimizer before packaging rewrites. Tagged `#! struct`
classes and `#! inline` static functions are optimized by default, with scalar replacement
and typed field reads enabled. `plugin_init` seeds the settings in `export.yml`.
Set `options.parser_settings.parse_gd.optimizer.enabled: false` to export an unoptimized
baseline, or override individual options per export entry. Reference types remain opt-in.
See [optimizer settings](export_ignore/doc/export_settings.md#gdscript-optimizer).

Validation:

```sh
godot --headless --path . --script res://addons/gdpackage/export_ignore/test/run_headless.gd
python3 addons/gdpackage/export_ignore/test/optimizer_export_smoke.py --godot /path/to/godot
```

The smoke test exports the fixture plugin with optimizer and packaging variants, then
executes their struct and inline workloads in isolated projects and compares results.
