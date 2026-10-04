# sweep

A command-line tool written in Zig that scans a directory and lists files grouped by extension, sorted alphabetically.

```
sweep [options] [directory]   # defaults to current directory if omitted

  -h, --help     Show help and exit
  -V, --version  Show the version and exit
```

Exits with status 1 if the directory can't be read and 2 for invalid arguments.

## CI

```sh
zig fmt --check src/main.zig   # formatting
zig fmt --check .              # formatting (entire project)
zig build                      # debug build
zig build test                 # tests
zig build test --release=safe  # tests with safety checks
zig build --release=safe       # release build with safety checks
zig build --release=fast       # release build
zig build --release=small      # size-optimized build
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
