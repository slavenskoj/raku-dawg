# Claude.md - Project-specific instructions for DAWG

## Known Issues

### Fez Upload Missing Builder.rakumod

**Issue**: When running `fez upload --dry-run`, the `lib/DAWG/Builder.rakumod` file is not included in the distribution bundle, even though:
- The file exists and is tracked by git
- The file is listed in META6.json provides section
- The file is required by the main module

**Root Cause**: This appears to be a bug in fez's bundling mechanism. The file is properly committed to git and `git archive` includes it correctly, but fez's internal bundling skips it.

**Workaround**: Create a manual distribution tarball using git archive and upload that instead:

```bash
# Create manual tarball with proper version prefix
git archive --format=tar.gz --prefix=DAWG-0.1.1/ -o DAWG-0.1.1.tar.gz HEAD

# Verify Builder.rakumod is included
tar -tzf DAWG-0.1.1.tar.gz | grep Builder

# Upload the manual tarball
fez upload --file=DAWG-0.1.1.tar.gz
```

## Development Commands

### Testing
```bash
# Run all tests
raku -I. t/*.rakutest

# Run specific test
raku -I. t/01-basic.rakutest
```

### Linting and Type Checking
Currently, Raku doesn't have standard linting/type-checking commands like npm. Tests serve as the primary validation mechanism.

## Project Structure

- `lib/DAWG.rakumod` - Main module
- `lib/DAWG/Builder.rakumod` - DAWG minimization builder (NOTE: affected by fez bug)
- `lib/DAWG/Node.rakumod` - Node structure implementation
- `lib/DAWG/Serializer.rakumod` - Binary and JSON serialization
- `lib/DAWG/Binary.rakumod` - Binary format handling
- `lib/DAWG/MMap.rakumod` - Memory-mapped file support
- `lib/DAWG/Search/` - Search implementations (Pattern, Fuzzy)
- `t/` - Test files
- `examples/` - Example usage scripts
- `tests/` - Additional test scripts (not part of distribution)

## Important Notes

1. The `raku-dawg/` subdirectory should remain in .gitignore - it's not part of the distribution
2. When updating version, remember to update both META6.json and the git archive command prefix
3. All module files should be listed in META6.json "provides" section