# TODO

## High Priority
- [x] **Fix Symlink Handling**: Currently, symlinks are ignored. Update logic to include symlinks that point to files.
- [x] **Logic Refactoring**: Move core file scanning and grouping logic from `src/main.zig` to `src/root.zig`. This will enable proper unit testing.
- [x] **Add Unit Tests**: Implement test blocks in `src/root.zig` to verify grouping and sorting behavior.
- [x] **Fix Windows Build**: `zig build -Dtarget=x86_64-windows` fails on Zig 0.17 because `init.minimal.args.iterate()` is a compile error on Windows. Use `init.minimal.args.iterateAllocator(allocator)` in `src/main.zig`.
- [x] **Trailing-Dot Names**: `std.Io.Dir.path.extension("foo.")` returns `"."`, so `foo.` lands in its own group, which `src/main.zig` then also prints as "No Extension", giving two such headings. Treat `"."` as `""` in `groupByExtension` and add a test.

## Improvements
- [x] **Argument Parsing**: Add support for standard flags like `--help` and `--version`.
- [x] **Hidden Files Support**: Add a command-line flag (e.g., `-a` or `--all`) to include files starting with `.`.
- [x] **Case-Insensitive Grouping**: Provide an option (or make it default) to group extensions like `.txt` and `.TXT` together.
- [x] **Memory Optimization**: Reduce redundant string allocations in the arena for repeated extensions.
- [x] **Sorting Optimization**: ~~Optimize the sorting process by sorting file lists during collection or more efficiently before output.~~ Won't do: each group is sorted once after collection (O(n log n) overall), and keeping lists sorted during collection would cost O(n) per insert.
- [x] **Graceful Error Handling**: Replace raw Zig error returns in `main` with user-friendly error messages. Include validation for invalid paths or cases where a file path is provided instead of a directory.
- [x] **Combined Short Flags**: Accept `-ai` as `-a -i`. `parseArgs` currently rejects it as an unknown option.
- [x] **Stdout Write Errors**: The `try` on stdout writes in `main` still lets `error.WriteFailed` escape (e.g. `sweep > /dev/full`). Report it with a `sweep:` message like other errors, and exit quietly on a broken pipe.
- [x] **Escape File Names**: Names containing newlines or control characters are printed raw. Quote or escape them, as `ls` does, so each name stays on one line.
- [x] **Non-ASCII Case Folding**: `-i` folds ASCII case only, so `.ÄBC` and `.äbc` stay separate. Documented as ASCII-only in the README and `--help`; Zig's std has no Unicode case tables.
- [x] **Windows Hidden Attribute**: Only names starting with `.` count as hidden, so files with the Windows hidden attribute are always listed. Documented in the README as a limitation.

## Maintenance
- [x] **Ghost Dependency**: Either use the `@import("sweep")` in `main.zig` after refactoring or remove the unused module import from `build.zig`.
- [x] **Don't Strip Test Binaries**: `.strip` is set on the exe's root module, which `exe_tests` reuses, so `zig build test --release=safe` prints no stack trace on panic. Apply strip only to the exe artifact.
- [x] **Respect Optimize in Library Tests**: The `sweep` module in `build.zig` has no `.optimize`, so `mod_tests` always builds in debug regardless of `--release=*`.
- [x] **Strip Build Option**: Add a `-Dstrip` option (defaulting to `optimize != .debug`) so release builds, especially ReleaseSafe, can keep symbols for stack traces and profiling.
- [x] **Document Zig Version**: `minimum_zig_version` is advisory and not enforced; state the required Zig version (0.17.0) in the README.
- [x] **Include LICENSE in Package**: Uncomment `"LICENSE"` in `.paths` in `build.zig.zon` so the MIT notice ships when the package is fetched.
- [ ] **Stable Zig Support**: Monitor the evolution of the experimental `std.process.Init` and `std.Io` APIs to ensure compatibility with future Zig releases.
- [x] **Continuous Integration**: Add a GitHub Actions workflow (there is no `.github/` yet) that, on every push and pull request:
  - Runs the README's CI commands: `zig fmt --check .`, `zig build`, `zig build test`, and `zig build test --release=safe`.
  - Tests on Linux, macOS and Windows. So far everything has only run on Linux; the symlink tests skip themselves on Windows.
  - Runs a second job against the Zig nightly build that is allowed to fail, as an early warning for **Stable Zig Support** when `std.process.Init` or `std.Io` change.
- [x] **Trim build.zig Comments**: Most of `build.zig` is the `zig init` template commentary (including its typos "business business" and "releative"). Cut it down so the project's own choices stand out: the strip option, the unstripped test module, and `build_options`.
- [x] **Update CI Actions**: Bumped `actions/upload-artifact` from v4 to v7; `actions/checkout@v7` and `mlugg/setup-zig@v2` were already current. tidyhome still needs the same change to keep the workflows identical.
- [x] **ReleaseSafe on Nightly**: The `zig-nightly` job runs only debug tests. Add `zig build test --release=safe` to catch more std changes early.
