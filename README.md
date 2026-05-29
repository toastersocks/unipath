# unipath

`unipath` is a small Swift command line tool for keeping one `PATH` list across fish, zsh, and bash.

It stores managed entries in:

```text
~/.config/unipath/paths
```

Then each shell can load that list at startup:

```fish
unipath env fish | source
```

```sh
eval "$(unipath env sh)"
```

## Warning

This is a personal project, mainly built for my own shell setup. It can modify shell startup files if you run `unipath init`, so read the output first and use it at your own risk.

Bug reports and contributions are welcome.

## Basic use

```sh
unipath import --home-relative --dedupe
unipath add --move ~/.local/bin
unipath remove ~/.bun/bin
unipath list --expanded
unipath doctor
```

`unipath import` snapshots the current `PATH`. By default it keeps paths as they appear. Use `--home-relative` to store paths under your home directory as `~`, and `--dedupe` to remove duplicate entries.

## Build

```sh
swift build
swift test
swift build -c release
```

