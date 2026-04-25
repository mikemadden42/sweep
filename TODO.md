# TODO

## High Priority
- [ ] **Fix Symlink Handling**: Currently, symlinks are ignored. Update logic to include symlinks that point to files.
- [ ] **Logic Refactoring**: Move core file scanning and grouping logic from `src/main.zig` to `src/root.zig`. This will enable proper unit testing.
- [ ] **Add Unit Tests**: Implement test blocks in `src/root.zig` to verify grouping and sorting behavior.

## Improvements
- [ ] **Argument Parsing**: Add support for standard flags like `--help` and `--version`.
- [ ] **Hidden Files Support**: Add a command-line flag (e.g., `-a` or `--all`) to include files starting with `.`.
- [ ] **Case-Insensitive Grouping**: Provide an option (or make it default) to group extensions like `.txt` and `.TXT` together.
- [ ] **Memory Optimization**: Reduce redundant string allocations in the arena for repeated extensions.
- [ ] **Graceful Error Handling**: Replace raw Zig error returns in `main` with user-friendly error messages.

## Maintenance
- [ ] **Ghost Dependency**: Either use the `@import("sweep")` in `main.zig` after refactoring or remove the unused module import from `build.zig`.
- [ ] **Stable Zig Support**: Monitor the evolution of the experimental `std.process.Init` and `std.Io` APIs to ensure compatibility with future Zig releases.
