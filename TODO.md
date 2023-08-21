# TODO

- make it so that ocamllsp works with source files
  - DONE but requires workaround for ocamllsp where projects must place a dummy
    (but valid) `dune-workspace` file at their root.
- separate opam switches for each package and one for build tools
  - this will allow the ocaml version required by each package to be different
    and also allow the ocaml version to be specified in toml, since the switch
    containing build tools can be installed before any toml gets read.
- allow non-concrete versions of dependencies
- bootstrapping a `spice` installation from the shell script
- a `package` command that generates archives suitable for installing with opam
  - add a `version` field to the manifest so the archives are correctly versioned
- bash autocompletion with `core.command`
- interdependent libraries
- lockfiles
- multiple interdependent packages in single workspace
- ocaml build scripts for all the non-trivial cases that would require a `rule` stanza in dune
- watch mode

## Hacks

Currently ocamllsp needs a dune-workspace file to find the .merlin file at the
project root. I'll either patch ocamllsp to not require this or fork my own
version for building non-dune projects but in the meantime the dune-workspace
file from `boot` is moved to the project root. This probably has implications
for how the transient dune projects behave since they are now part of a
workspace.

## Subcommands

- `new` initializes a project (also available in `spice` shell script)
- `setup` run it in a fresh clone of an existing project to install all its dependencies (also available in `spice` shell script)
- `build` updates lockfile if deps have changed, downloads deps if lockfile has changed, generates dune project, builds
- `run` everything in `build` but then also runs the named binary or the only binary if there is just one
- `package` generates dune project (including opam file) and creates tarball suitable to build with opam
- `watch` runs `build` in response to file changes
- `update` runs `opam update` (just for the current switch)
- `upgrade` regenerates a lockfile

## Lockfiles

Each package gets a lockfile. The lockfile is a function of the package's
dependencies and a revision of the opam repo. The lockfile contains a copy of
the package's dependencies so `spice` can tell when a dependency has changed.
Changing a dependency re-solves the lockfile. We'll use 0install to solve the
dependencies for the lockfile. For now the lockfile will just be used to create
`dune-project` files and opam files with explicit, concrete dependencies but
this could change to generating dune lockdirs as dune's package management
features mature.

## Gaps

The user will still have to run `opam init` once before this tool will work as
opam is needed to install dune regardless of dune's own package management
ability.
