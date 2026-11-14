# Releases

## Release Export

A normal export crawls the project as it is on disk, uncommitted changes and all. A release export
builds from tags instead:

```text
gdpackage export --release my_plugin
gdpackage export --release --refresh my_plugin
gdpackage export --release --local my_plugin
```

1. **Resolve.** The plugin's `version=` must have a matching tag (`1.2.0` or `v1.2.0`) on its
   `origin` remote. Its `build_require` and `compile_require` (below) are read from
   the package's export config *at that tag*, then each dep's the same way at its tag, and so
   on. When two plugins ask for different tags of one repo, the highest wins (Go's minimal
   version selection). Every requirement needs an `@tag`; an untagged one fails the export and
   prints the chain that asked for it.
   Within a compatible major line, a lower explicit requirement produces a warning when another
   dependency of that package requires a higher version. For example, A requiring C@0.2.0 and B,
   where B requires C@0.2.1, selects C@0.2.1 and warns that A should raise its C requirement.
   Every selected package is checked against its own dependency subtree; a version raised only
   by its parent or an unrelated branch does not warn. Incompatible major lines still fail;
   v0 and v1 share one compatibility line.
2. **Fetch.** Repos are mirrored under the OS cache dir (`gdpackage/repos`). A tag already
   mirrored is never re-fetched. `--refresh` checks every cached tag against its remote and fails
   if one was moved.
3. **Workspace.** Each dependency's addon folder, at its tag, is copied into its install path (see
   "Where a dependency installs" below). A released `gdpackage` (the
   toolchain, below) runs the export headless there. Workspaces are reused while the resolved tags
   and the toolchain stay the same.
4. **Verify.** Every exported variant is installed into an empty project, along with its
   `compile_require` deps (and whatever those need), and every script and resource is loaded. Any
   parse, compile or load error moves the output to `<plugin_folder>-unverified`.

## Build requirements

A release export reads requirements from the main body of the export config, shared
by every export entry. Omitted `build_require` and `test_require` default to `"@require"`,
which expands the package cfg's `require=` list. `compile_require` defaults to `[]`.
Set an explicit list to replace the default, or include `"@require"` alongside extra
dependencies. Use `[]` when the package needs no dependencies for that stage.

```yaml
build_require:
  - brohd11/godot-addon-lib@v2.1.2
  - brohd11/godot-yaml-parser@v2.1.0
compile_require:
  - brohd11/godot-tree-sitter-gd@v1.0.5
```

- `build_require`: placed in the workspace; the export bundles whatever it uses.
- `compile_require`: also installed beside the exported plugin when it is verified, for extensions
  or plugins yours is meant to run with. A repo in both lists counts as `compile_require`.
- Each key takes a list of specs or a single spec.
- `"@require"` uses the package cfg's `require=` list from `[package]`, legacy `[addon]`,
  or `[plugin]`, in that order. It is valid in `build_require` and `test_require`, but
  not `compile_require`. `require update --export-config` writes an explicit build
  list and drops `"@require"` rather than expanding it.
- The config lives in `_export_ignore/` or `export_ignore/`; when both hold one, `_export_ignore`
  wins. New configs use `export.yml`; legacy filenames remain supported. A package
  without an export config still gets the defaults from its cfg's `require=` list.
  A library can carry an export config containing only requirement keys.
- The export-ignore folder is omitted from releases. Their cfg `require=` lists the
  dependencies that an installer must add, as configured by `exported_require` below.

## Dependencies left for the installer

Development cfg `require=` lists commonly include libraries that the exporter bundles.
The exported cfg replaces that list with `exported_require` from the export config,
which defaults to `[]`. List dependencies here only when gdaddon must install them
beside your package. `options.exported_deps` is a legacy spelling.

For example, an extension needed both during verification and after installation:

```yaml
compile_require:
  - brohd11/godot-tree-sitter-gd@v1.0.5
exported_require:
  - brohd11/godot-tree-sitter-gd@v1.0.5
```

Release exports warn when a compile requirement is missing from `exported_require`.
For test-only dependencies, see [Testing](testing.md).

## Dependency kinds

A plain `owner/repo@v1.0.0` means the release, picked the way gdaddon picks
it: the release's single uploaded asset, or the tag's source when nothing was uploaded (or the tag
has no release). Several uploads fail as ambiguous. `owner/repo/source@v1.0.0` always takes the
tag's source. A host can lead the spec (`gitlab.com/owner/repo`); only a first segment containing a
dot is read as a host. Releases are looked up through the GitHub API, which allows 60 requests an
hour without a token; set `GITHUB_TOKEN` to raise that. Assets are cached per tag.

## Where a dependency installs

A package can be laid out three ways, and the same rules as gdaddon place it:

- a cfg at the package root: the package is the addon, and its cfg must say where it goes with
  `path="addons/..."` (or `dir=`); without it the export fails
- a whole Godot project: the shallowest `addons/` folder is the anchor, so
  `addons/_lib/yaml_parser` installs at `res://addons/_lib/yaml_parser`
- anything else, such as a release zip: the cfg folder's path under the package root (after a single
  wrapper folder is stripped) is its path under `addons/`

When a package holds several addon folders, only the one whose cfg `url=` names the repo is used.
A `path=`/`dir=` in the chosen cfg always wins over the derived location.

## Requirement maintenance

To find out what to require, run `gdpackage require check --all my_plugin`. It runs the export crawl
without writing anything and lists the packages the export pulls in. A package is the
nearest folder with a `plugin.cfg` or `package.cfg` (or a legacy `addon.cfg`/`version.cfg`), so
every
file of one release counts once. Its identity is the git `origin` when the folder is a checkout, or
the
cfg `url=` for a package installed from a release zip. Packages are grouped by the package whose
export config should list them, and each is marked `declared (build)`, `declared (compile)` or
`MISSING`. Missing export configs are flagged in the crawl report; dependency resolution
still applies the cfg `require=` defaults described above.

`gdpackage require check my_plugin` prints only that plugin's own list, one `owner/repo@tag`
per line and nothing else, for piping.

`gdpackage require check --tags my_plugin` checks declared build, compile and test requirements
at their actual tags, then resolves their full dependency graph. Missing tags, invalid packages
and incompatible graphs fail the check. Understated requirements produce `WARN` lines without
failing it; the same warnings appear during release exports and test CI. The target needs a
package cfg but does not need its own Git origin or tag. Requirements remain minimums: the
highest required version is selected, and warnings do not rewrite declarations. A package that
only uses C indirectly through B does not need to declare C itself.

`gdpackage require update my_plugin` writes that list into the plugin's own cfg `require=`;
`--export-config` writes `build_require` instead. Only the target's list is changed. A tag is `v`
plus
the required package's cfg `version=`; when that tag isn't in the package's checkout yet you get a
warning, since tagging comes after the update, and a package with no version to pin is an error that
writes nothing at all. Entries the config already lists keep their tag, so a deliberate older pin
survives; `--overwrite` re-pins them (a leading host and the `/source` marker are kept), and
`--prune` drops the ones the crawl no longer finds. A package already under `compile_require` is
left to it. Comments and key order elsewhere in the selected file are untouched.

## Trying local tags

`--local` is for trying a release before pushing anything. Every repo with a checkout in this
project is fetched from that checkout instead of its remote; repos without one (a checkout counts
only if its `origin` is the same repo) still come from their remote, with a warning. A missing
local tag is an error, never a fallback. It is still tag-pinned, so only committed, tagged files are
used - you tag, but
don't push. A local tag you move is followed rather than rejected. Lock entries are marked
`"source": "local"`, and each local tag that isn't on `origin` yet gets a warning.

## Toolchain and lock file

The export is run by a *released* gdpackage rather than the one in this
project, so the exporter's own libraries can't clash with the pinned ones. Its version is
`toolchain` under `options` in the export config, or this project's gdpackage version when
unset. Normally it is the GitHub release zip (`gdpackage-<version>.zip` on tag
`v<version>`), downloaded once into the cache's `toolchains` folder and reused; `--refresh`
downloads it again. `--local` doesn't change the toolchain selection.
If the dev version is ahead of the latest release, pin `toolchain` to a released version. If the
toolchain's export scripts don't compile, the release export fails before verification.

GDPackage's own release is the exception: its tagged source serves as the toolchain
inside the build workspace. Its test workspace similarly runs the checked-out source.

The export carries `.export_lock.json` (repo, tag, commit, path per dependency, and the toolchain)
in place of
`.export_git_details`. Entries marked `verify` are the ones the compile check installed. The
exported cfg's `require=` list comes from `exported_require`; the source cfg is unchanged.

## Release CI

Generate a caller workflow from the editor console:

```text
gdpackage ci release_workflow my_plugin
```

This writes `.github/workflows/release.yml` at the package repository root without
overwriting an existing file. For a package below the root, pass `--allow-project-root`
to write there and set `package-dir`.

The workflow builds and verifies version tags matching the package cfg's `version=`
and attaches the resulting zips to a GitHub release. Push dependency tags first.
A manual dispatch builds the matching tag without publishing. Build zips are also
uploaded as workflow artifacts; failures upload export diagnostics.

The generated caller selects the running editor's Godot build through `godot-version`.
The reusable workflow uses a released GDPackage toolchain; set `toolchain-version`
to pin it. `install-path` and `package-dir` override layout detection when needed.
The reusable workflow's `publish: false` builds and verifies without publishing.

See [Commands](commands.md#headless-entry-points) for the headless release entry point
and [Testing](testing.md#github-actions) for the test workflow.
