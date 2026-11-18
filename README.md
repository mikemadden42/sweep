# sweep

A command-line tool written in Zig that scans a directory and lists files grouped by extension, sorted alphabetically.

```
sweep [options] [directory]   # defaults to current directory if omitted

  -a, --all          Include hidden files (names starting with ".")
  -i, --ignore-case  Ignore case when grouping extensions and sorting names
  -h, --help         Show help and exit
  -V, --version      Show the version and exit
```

File names are printed one per line. Control characters are shown as C-style escapes (`\n`, `\t`, `\x1b`) and backslashes are doubled, so a name with a newline in it can't pass for two names.

Exits with status 1 if the directory can't be read or the output can't be written (silently, if the output pipe is closed, as with `sweep | head`), and 2 for invalid arguments.

## Requirements

Zig 0.17.0 or later. The build uses `std.process.Init` and `std.Io` APIs that are not available in earlier releases.

## CI

GitHub Actions (`.github/workflows/ci.yml`) checks formatting, builds, and runs the tests in debug and ReleaseSafe on Linux, macOS and Windows for every push to `main` and every pull request. A separate job builds and tests against Zig nightly; it is allowed to fail and never blocks a merge.

```sh
zig fmt --check src/main.zig   # formatting
zig fmt --check .              # formatting (entire project)
zig build                      # debug build
zig build test                 # tests
zig build test --release=safe  # tests with safety checks
zig build --release=safe       # release build with safety checks
zig build --release=fast       # release build
zig build --release=small      # size-optimized build
zig build --release=safe -Dstrip=false  # release build that keeps debug symbols
```

## Cross Compilation

```sh
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-windows
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86_64-macos
zig build -Dtarget=x86_64-freebsd
```
