# GDPackage

GDPackage is a plugin and tool for working with GDScript "packages". A package is a set of files that can declare other packages as dependencies. These can be used during CI testing or building releases.

Companion tool [gdaddon](https://github.com/brohd11/gdaddon) uses the same package format to install a package and dependencies into your project, for releases or dev project setup.

## Install

Download the release and place the contents in the addons folder.

Using [Editor Console](https://github.com/brohd11/godot-editor-console) plugin is suggested, it provides easy access to gdpackage commands in the editor.

### Install with gdaddon

Navigate to your project in terminal, then run:
```sh
gdaddon install brohd11/godot-gdpackage/release
gdaddon install brohd11/godot-editor-console/release
```

## Purpose

My main motivation for creating this was to use shared libraries between plugins without needing to maintain a copy of the code in every repository.

For a plugin to function properly while organizing like this, you need to either:
1. Have a user download any shared libraries (friction)
2. Maintain a copy of your libraries in your plugin

Instead, this allows you to `require` a repo as a dependency in your package config file. Which the plugin can use to create a release package with all the used files bundled in.

## Export/Release

The standard export process does a couple of things:
- Checks every GDScript, Tscn and Tres file for used files, recursively
- Only used files are bundled
- Global Classes have their class_name stripped and are instead preloaded in every user of the file. You can set which files to keep global in export settings

This process is ideal for plugins, allowing you to build with global classes in your plugin development repo, but distribute without polluting the global namespace.

The "release" export (CI compatible) does a bit more:
- Downloads every required package, recursively
- Performs the standard export
- Compile checks the result
- Publishes the packaged release

There is a template CI release workflow that points at this repo, which runs the release on every tagged "v*" push.

## Testing

There is also a template CI test workflow. It will run your tests in a project with all declared dependencies present.
This allows you to use your own test formats, or you can require GUT or GDUnit in `test_require` of `export.yml` to use them instead.

## Package Format

A package is a folder with a `package.cfg` file (or `plugin.cfg`, the files are treated the same). It also typically has an `_export_ignore/` folder where the `export.yml` file is located. You can also store things here that are not intended for a release like extended documentation, test fixtures, etc.

The intended repo set-up is submodule style, the root of the repo being the package itself (see this repo). Adding `path="addons/my_package"` to the package.cfg will tell GDPackage where the files should be located on install.

A standard Godot plugin/project structure also works if there is only 1 folder in `res://addons/`.

An example of a [plugin.cfg](./plugin.cfg) that declares dependencies.

The package fields are:
- `name`
- `version`
- `require`
- `path`
- `url` (optional)
- `minimum_engine_version` (optional)

## Quick Start

Enable GDPackage in **Project Settings -> Plugins**. For an existing plugin at `res://addons/my_plugin`, you can initialize, open the gui, and export:

```text
# "my_plugin" is a relative path from res://addons/. Absolute paths are accepted too

gdpackage init plugin my_plugin
gdpackage open gui my_plugin
gdpackage export my_plugin

gdpackage ci test_workflow my_plugin
gdpackage ci release_workflow my_plugin
```

The `init` command creates `_export_ignore/export.yml`, where build/release settings are stored. See [Setup](export_ignore/doc/setup.md) for package creation and GUI instructions.

Test and release workflows can be generated from the console. They point at the gdpackage repo, so they get updates to the workflow without needing to be updated in the package.

## Other plugins
- [Namespace](https://github.com/brohd11/godot-namespace.git) recognizes the package format and will build its global classes within your package.

## Documentation

- [Setup and exporting](export_ignore/doc/setup.md)
- [Commands](export_ignore/doc/commands.md)
- [Testing and test CI](export_ignore/doc/testing.md)
- [Dependencies and tags](export_ignore/doc/dependencies.md)
- [Optimization and compatibility](export_ignore/doc/optimization.md) - **Experimental**
- [Releases and release CI](export_ignore/doc/releases.md)
- [Shipping documentation](export_ignore/doc/shipping_docs.md)
- [Export settings reference](export_ignore/doc/export_settings.md)

[YouTube walkthrough](https://youtu.be/G0ZlF8FJ94U)

