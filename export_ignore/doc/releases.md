# Releases

## Release Export

A normal export crawls the project as it is on disk, uncommitted changes and all. A release export builds from tags instead:

```text
gdpackage export --release my_plugin
gdpackage export --release --refresh my_plugin
gdpackage export --release --local my_plugin
```

1. **Resolve.** The package's `version=` must have a matching tag (`1.2.0` or `v1.2.0`) on its `origin` remote. Requirements are read from the export config at that tag, then from each dependency at its tag, and so on. See [Version selection](#version-selection).
2. **Fetch.** Repos are mirrored under the OS cache dir (`gdpackage/repos`). A mirrored tag is never re-fetched. `--refresh` checks every cached tag against its remote and fails if one was moved.
3. **Workspace.** Each dependency's addon folder, at its tag, is copied into its [install path](#where-a-dependency-installs). A released GDPackage (the [toolchain](#toolchain-and-lock-file)) runs the export headless there. Workspaces are reused while the resolved tags and the toolchain stay the same.
4. **Verify.** Every exported variant is installed into an empty project with its `compile_require` deps (and whatever those need), and every script and resource is loaded. Any parse, compile or load error moves the output to `<plugin_folder>-unverified`.

## Version selection

- Every requirement needs an `@tag`. An untagged one fails the export and prints the chain that asked for it.
- When packages ask for different tags of one repo, the highest wins (Go's minimal version selection).
- Incompatible major lines fail. v0 and v1 share one compatibility line.
- An understated requirement warns. If A requires C@0.2.0 and B, and B requires C@0.2.1, then C@0.2.1 is selected and A is told to raise its C requirement.
- A package is only checked against its own dependency subtree. A version raised by its parent or an unrelated branch does not warn.
- A package that only uses C indirectly through B does not need to declare C.

## Build requirements

Requirements go in the main body of the export config and are shared by every export entry:

```yaml
build_require:
  - brohd11/godot-addon-lib@v2.1.2
  - brohd11/godot-yaml-parser@v2.1.0
compile_require:
  - brohd11/godot-tree-sitter-gd@v1.0.5
```

- `build_require` - placed in the workspace; the export bundles whatever it uses. Defaults to `"@require"`.
- `compile_require` - also installed beside the exported package when it is verified, for extensions or plugins it is meant to run with. Defaults to `[]`. A repo in both lists counts as `compile_require`.
- `test_require` - test-only dependencies, defaults to `"@require"`. See [Testing](testing.md#test-ci).
- `"@require"` expands to the package cfg's `require=` list. Use it alongside extra entries, or use `[]` for no dependencies. Not valid in `compile_require`.
- Each key takes a list of specs or a single spec.
- A package without an export config still gets the `require=` defaults. A library's export config can hold only requirement keys.

## Dependencies left for the installer

A development cfg's `require=` usually names libraries that the exporter bundles. The exported cfg replaces that list with `exported_require` from the export config, default `[]`. List a dependency there only when gdaddon must install it beside the package.

For example, an extension needed both during verification and after installation:

```yaml
compile_require:
  - brohd11/godot-tree-sitter-gd@v1.0.5
exported_require:
  - brohd11/godot-tree-sitter-gd@v1.0.5
```

Release exports warn when a compile requirement is missing from `exported_require`.

## Dependency kinds

- `owner/repo@v1.0.0` - the release, picked the way gdaddon picks it: the release's single uploaded asset, or the tag's source when nothing was uploaded or the tag has no release. Several uploads fail as ambiguous.
- `owner/repo/source@v1.0.0` - always the tag's source.
- `gitlab.com/owner/repo@v1.0.0` - a host can lead the spec. Only a first segment containing a dot is read as a host.

Releases are looked up through the GitHub API, which allows 60 requests an hour without a token. Set `GITHUB_TOKEN` (or `GH_TOKEN`) to raise that. With a token, assets download through the API, which a private repository needs. Assets are cached per tag.

## Where a dependency installs

A package can be laid out three ways, placed by the same rules as gdaddon:

- A cfg at the package root: the package is the addon, and its cfg must say where it goes with `path="addons/..."` (or `dir=`). Without it the export fails.
- A whole Godot project: the shallowest `addons/` folder is the anchor, so `addons/_lib/yaml_parser` installs at `res://addons/_lib/yaml_parser`.
- Anything else, such as a release zip: the cfg folder's path under the package root (after a single wrapper folder is stripped) is its path under `addons/`.

When a package holds several addon folders, only the one whose cfg `url=` names the repo is used. A `path=`/`dir=` in the chosen cfg always wins over the derived location.

## Requirement maintenance

A package is the nearest folder with a `plugin.cfg` or `package.cfg`, so every file of one release counts once. Its identity is the git `origin` for a checkout, or the cfg `url=` for a package installed from a release zip.

`gdpackage require check my_plugin`:

- Plain, it prints the package's own list, one `owner/repo@tag` per line and nothing else, for piping.
- `--all` runs the export crawl without writing anything and lists every package the export pulls in. They are grouped by the package whose export config should list them, each marked `declared (build)`, `declared (compile)` or `MISSING`. Missing export configs are flagged.
- `--tags` checks declared build, compile and test requirements at their tags, then resolves the full graph. Missing tags, invalid packages and incompatible graphs fail. Understated requirements print `WARN` lines without failing; the same warnings appear in release exports and test CI. The target needs a package cfg, but not its own Git origin or tag.

`gdpackage require update my_plugin`:

- Writes the list into the package's own cfg `require=`. `--export-config` writes an explicit `build_require` instead, dropping `"@require"`.
- Only the target's list changes. Comments and key order elsewhere in the file are untouched.
- A tag is `v` plus the required package's cfg `version=`. If that tag isn't in the package's checkout yet it warns, since tagging comes after the update. A package with no version to pin is an error, and nothing is written.
- Entries already listed keep their tag, so a deliberate older pin survives. `--overwrite` re-pins them (a leading host and the `/source` marker are kept). `--prune` drops the ones the crawl no longer finds.
- A package already under `compile_require` is left there.

## Trying local tags

`--local` is for trying a release before pushing anything.

- Every repo with a checkout in this project is fetched from that checkout instead of its remote. A checkout only counts if its `origin` is the same repo.
- Repos without a checkout still come from their remote, with a warning.
- It is still tag-pinned: only committed, tagged files are used. Tag, but don't push.
- A missing local tag is an error, never a fallback. A local tag that was moved is followed rather than rejected.
- Lock entries are marked `"source": "local"`, and each local tag that isn't on `origin` yet gets a warning.

## Toolchain and lock file

The export is run by a *released* GDPackage rather than the one in this project, so the exporter's own libraries can't clash with the pinned ones.

- The version is `options.toolchain` in the export config, or this project's GDPackage version when unset.
- It is the GitHub release zip (`gdpackage-<version>.zip` on tag `v<version>`), downloaded once into the cache's `toolchains` folder and reused. `--refresh` downloads it again. `--local` doesn't change the toolchain.
- If the dev version is ahead of the latest release, pin `toolchain` to a released version.
- If the toolchain's export scripts don't compile, the release export fails before verification.
- GDPackage's own release is the exception: its tagged source is the toolchain inside the build workspace, and its test workspace runs the checked-out source.

The export carries `.export_lock.json`: repo, tag, commit and path per dependency, plus the toolchain. Entries marked `verify` are the ones the compile check installed.

## Release CI

Generate a caller workflow from the editor console:

```text
gdpackage ci release_workflow my_plugin
```

- Writes `.github/workflows/release.yml` at the package repository root. An existing file is not overwritten. For a package below the root, pass `--allow-project-root` to write there and set `package-dir`.
- The workflow builds and verifies version tags matching the package cfg's `version=`, and attaches the zips to a GitHub release. Push dependency tags first.
- A manual dispatch builds the matching tag without publishing, as does `publish: false`.
- Build zips are also uploaded as workflow artifacts. Failures upload export diagnostics.
- `godot-version` is set to the running editor's Godot build.
- The reusable workflow uses a released GDPackage toolchain; set `toolchain-version` to pin it.
- `install-path` and `package-dir` override layout detection.

See [Commands](commands.md#headless-entry-points) for the headless release entry point and [Testing](testing.md#github-actions) for the test workflow.

### Release notes

The reusable workflow can write the release's notes from conventional commit messages with [git-cliff](https://git-cliff.org). It is off by default; turn it on in the caller:

```yaml
jobs:
  release:
    uses: brohd11/godot-gdpackage/.github/workflows/package-release.yml@main
    with:
      release-notes: true
```

- A `cliff.toml` at the repository root is used when there is one. Otherwise GDPackage's default, which lists breaking changes, `feat`, `fix` and `perf` commits and skips the rest.
- A tag with a `-suffix` (`v1.2.0-beta.1`) covers the changes since the previous tag. Any other tag covers the changes since the previous tag without a suffix, so it includes its pre-releases.
- For a package below the repository root, only commits touching its folder are listed.
- Notes are set when the workflow creates the release. A release that already exists for the tag keeps its own.
- A manual dispatch shows the notes in the run summary without publishing them.
- If generation fails the release is still published, with a placeholder note.

### Private dependencies

The workflows fetch with the calling repository's own token, which reads that repository only. A private package with public dependencies works as is.

To depend on other private repositories, create a token that can read them (a fine-grained personal access token with *Contents: read* on those repositories, plus the package's own when it is private), store it as a secret, and pass it from the caller job:

```yaml
jobs:
  release:
    uses: brohd11/godot-gdpackage/.github/workflows/package-release.yml@main
    secrets:
      deps-token: ${{ secrets.GDPACKAGE_DEPS_TOKEN }}
```

- The test workflow takes the same secret.
- The token is only used to fetch from github.com. Publishing still uses the repository's own token.
- Pull requests from forks receive no secrets, so their runs can't reach private dependencies.
- Released zips of a private dependency (`/release`) need a toolchain newer than 0.12.0. Source dependencies work with any.

Outside CI, private dependencies are fetched with your own Git credentials.
