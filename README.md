# DAWG - Directed Acyclic Word Graph for Raku

A high-performance, memory-efficient data structure for storing and searching large sets of strings. This Raku implementation provides both traditional and zero-copy memory-mapped access to DAWG structures.

DAWGs, also known as [deterministic acyclic finite state automaton](https://en.wikipedia.org/wiki/Deterministic_acyclic_finite_state_automaton), were pioneered in the 1980s for spell-checkers and have since become fundamental in computational linguistics. They power modern applications from mobile keyboard autocorrect to DNA sequence analysis, word game AI, and full-text search engines. 

## Table of Contents

- [Memory Mapping: Zero-Copy Performance](#memory-mapping-zero-copy-performance)
- [Traditional DAWG: In-Memory Performance](#traditional-dawg-in-memory-performance)
- [Background](#background)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Advanced Search Features](#advanced-search-features)
- [Example: Spell Checker](#example-spell-checker)
- [API Reference](#api-reference)
  - [Methods](#methods)
  - [DAWG::MMap Methods](#dawgmmap-methods)
- [Performance](#performance)
  - [Benchmarks](#benchmarks)
- [Character Encoding and Storage](#character-encoding-and-storage)
  - [ASCII Optimization](#ascii-optimization)
  - [Compressed Unicode Mode (7-bit)](#compressed-unicode-mode-7-bit)
  - [Why UTF-32?](#why-utf-32)
  - [Automatic Type Management](#automatic-type-management)
  - [Working with Optimizations](#working-with-optimizations)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [Author](#author)
- [License](#license)
- [See Also](#see-also)

## Memory Mapping: Zero-Copy Performance

Memory mapping fundamentally changes how we access large data structures. Instead of loading an entire file into RAM, memory mapping creates a virtual view where file contents appear as regular memory. The operating system loads only the pages you actually access, on demand. For DAWGs, this means:

- **Instant startup**: A 1GB DAWG "loads" in milliseconds versus seconds
- **Shared memory**: Multiple processes can share the same DAWG without duplication
- **OS-managed caching**: Frequently accessed nodes stay in RAM automatically
- **Graceful scaling**: Works seamlessly whether your DAWG is 1MB or 100GB+

Our implementation uses fixed-width encodings specifically to enable efficient memory mapping - each character lookup translates directly to a memory address calculation.

## Traditional DAWG: In-Memory Performance

Traditional (non-memory-mapped) DAWGs load the entire structure into RAM at startup. While this requires more initial time and memory, it provides optimal runtime performance:

- **Fastest lookups**: All data in RAM means no page fault delays
- **Predictable latency**: No OS intervention during traversal
- **Memory ownership**: The process controls the memory lifecycle
- **Ideal for**: Frequently accessed dictionaries, real-time systems, smaller datasets

Choose traditional loading when lookup speed is critical and you can afford the memory overhead. Choose memory mapping when dealing with large dictionaries or when startup time matters more than lookup speed.

## Background

DAWGs, also known as [deterministic acyclic finite state automaton](https://en.wikipedia.org/wiki/Deterministic_acyclic_finite_state_automaton), were pioneered in the 1980s for spell-checkers and have since become fundamental in computational linguistics. They power modern applications from mobile keyboard autocorrect to DNA sequence analysis, word game AI, and full-text search engines. 

The DAWG structure automatically identifies and shares common prefixes (like a trie) and common suffixes (through node minimization). For example, "running", "runner", and "runs" share the prefix "run", while "singing" and "running" share the suffix "ing" through the same graph nodes. This dual compression of both prefixes and suffixes enables DAWGs to compress dictionaries by 10-50x compared to plain text while maintaining O(m) lookup time.

DAWGs are particularly effective for:
- **Morphologically rich languages**: Where word forms share common roots and inflections
- **Technical vocabularies**: Where terms share common prefixes and suffixes (e.g., medical terminology)
- **Historical text corpora**: Where spelling variants share common stems

Our implementation's additional automatic 7-bit unicode compression mode provides further benefits for:
- **European scripts**: All modern European and most historic European alphabets fit within 89 characters (including uppercase/lowercase), enabling 7-bit compression
- **Middle Eastern and North African scripts**: Abjads and alphabets with 20-40 base letters
- **Caucasian and Central Asian scripts**: Alphabets typically using 30-45 letters
- **Southeast Asian scripts**: Writing systems with 40-60 base characters
- **Specialized dictionaries**: Phonetic (IPA), mathematical, chemical notation with controlled symbol sets
- **Domain-specific databases**: Technical glossaries, legal terminology with limited special characters
- **Private use areas**: Custom symbols for specialized applications work quickly and seamlessly
- **Emoji:** Emoji and other grapheme clusters are automatically handled as single characters saving even more space

The 7-bit compressed mode stores all characters in single bytes, achieving 50-75% space reduction versus UTF-8 (which uses 2-3 bytes for non-ASCII characters), making multi-gigabyte dictionaries practical on memory-constrained devices. Importantly, this compression is completely language-agnostic: any Unicode character from any script can be included - whether it's 中文, العربية, עברית, ไทย, or even emoji 🎯. The only constraint is the total number of unique characters (≤89), not which characters they are. When character diversity exceeds 89 unique characters, the DAWG automatically uses fixed-width UTF-32 encoding to support unlimited Unicode.

Fixed-width encoding is crucial for DAWG performance, which is why all our modes use it: ASCII and 7-bit compressed use 1 byte per character, while UTF-32 uses 4 bytes per character. Unlike variable-length encodings (UTF-8/UTF-16), where finding the Nth character requires scanning from the beginning, fixed-width encodings allow direct array-style access: the Nth character is always at byte offset N×width. This enables our memory-mapped DAWGs to traverse edges with simple pointer arithmetic rather than complex decoding loops. During graph traversal, each edge lookup becomes a direct memory read at a calculated offset, maintaining O(1) time per character. This is especially important for memory-mapped files, where sequential scanning would trigger multiple page faults, but direct access allows the OS to efficiently load only the needed memory pages.

## Features

- **Fast lookups** - O(m) time complexity where m is the length of the string
- **Space efficient** - Automatically minimizes the structure by sharing common suffixes
- **Prefix search** - Find all words with a given prefix efficiently
- **Value storage** - Associate arbitrary values with each word
- **Multiple serialization formats**:
  - JSON (portable, human-readable)
  - Binary (compact, fast loading)
  - Memory-mapped (zero-copy, instant loading)
- **Zero-copy loading** - Memory-mapped access for instant startup
- **ASCII optimization** - Automatic 75% space reduction for ASCII-only data
- **Compressed Unicode** - Maps up to 89 unique characters to single bytes for 75% space reduction
- **Pure Raku** - No external dependencies except JSON::Fast and NativeCall

## Installation

You can install DAWG directly from the zef ecosystem:

```bash
zef install DAWG
```

Or install from source (recommended for the latest features):

```bash
git clone https://github.com/slavenskoj/raku-dawg.git
cd raku-dawg
zef install .
```

> **Note**: When using save/load functionality, it's recommended to use the binary format methods 
> (`save-binary` and `load`) as they provide better performance and reliability compared to JSON serialization.

## Quick Start

```raku
use DAWG;

# Create a new DAWG
my $dawg = DAWG.new;

# Add words
$dawg.add("apple");
$dawg.add("application", 42);    # with optional value
$dawg.add("apply", { id => 3 }); # any value type

# Minimize the structure (do this after adding all words)
$dawg.minimize;

# Check if words exist
say $dawg.contains("apple");     # True
say $dawg.contains("banana");    # False

# Lookup with values
my $result = $dawg.lookup("application");
say $result<value>;  # 42

# Find all words with a prefix
my @words = $dawg.find-prefixes("app");
# Returns: ["apple", "application", "apply"]

# Save and load
$dawg.save("my-dictionary.dawg.json");        # JSON format
$dawg.save-binary("my-dictionary.dawg.bin");  # Binary format
my $loaded = DAWG.load("my-dictionary.dawg.bin");  # Auto-detects format
```

### Advanced Search Features

The DAWG module includes separate search modules for pattern matching and fuzzy search:

```raku
use DAWG::Search::Pattern;
use DAWG::Search::Fuzzy;

# Pattern matching with wildcards
my $pattern-search = DAWG::Search::Pattern.new(:$dawg);
my @matches = $pattern-search.find('a?p*');     # apple, apply, application
@matches = $pattern-search.find('*tion');       # application, creation, etc.

# Fuzzy search with edit distance  
my $fuzzy-search = DAWG::Search::Fuzzy.new(:$dawg);
my @suggestions = $fuzzy-search.search('aple', :max-distance(2));
# Returns: [{word => 'apple', distance => 1}, ...]

# Find closest matches
my @closest = $fuzzy-search.closest('compter', :limit(3));
# Returns the 3 closest words by edit distance
```

## Example: Spell Checker

The DAWG module includes a complete spell checker example that demonstrates fuzzy matching capabilities:

```bash
# Run in demo mode
raku examples/spell-checker.raku

# Run in interactive mode
raku examples/spell-checker.raku --interactive

# Customize parameters
raku examples/spell-checker.raku --max-distance=3 --suggestions=10
```

The spell checker demonstrates:

- Loading dictionaries into DAWG structures
- Real-time spell checking with fuzzy matching
- Providing ranked suggestions by edit distance
- Handling various types of spelling errors (missing letters, transpositions, etc.)

Example output:

```
Checking 'helo' (Missing letter): ✗ Misspelled
  Suggestions: hello (distance: 1)

Checking 'wrold' (Transposed letters): ✗ Misspelled
  Suggestions: world (distance: 2), word (distance: 2)

Checking 'algorythm' (Common misspelling): ✗ Misspelled
  Suggestions: algorithm (distance: 1)
```



## API Reference

### Methods

#### `new()`
Creates a new empty DAWG.

#### `add(Str $word, $value?)`
Adds a word to the DAWG with an optional associated value. Automatically upgrades the DAWG type when necessary:
- **ASCII → Compressed Unicode (7-bit)**: When Unicode is added and total unique characters ≤89
- **ASCII → UTF-32**: When Unicode is added and total unique characters >89
- **Compressed Unicode (7-bit) → UTF-32**: When new Unicode characters outside the mapping are added
- **UTF-32 → Compressed Unicode (7-bit)**: When beneficial (≤89 unique characters with Unicode)

For compressed Unicode DAWGs, throws an error only if reserved mapping characters are used.

#### `contains(Str $word) --> Bool`
Returns True if the word exists in the DAWG.

#### `lookup(Str $word) --> Hash`
Returns a hash with the word and its associated value, or Nil if not found.

#### `find-prefixes(Str $prefix) --> Array`
Returns an array of all words that start with the given prefix.

#### `all-words() --> Array`
Returns an array of all words in the DAWG.

#### `minimize()`
Minimizes the DAWG by merging equivalent nodes. Call this after adding all words for optimal space efficiency.

#### `save(Str $filename)`
Saves the DAWG to a file in JSON format.

#### `save-binary(Str $filename)`
Saves the DAWG to a file in binary format (more compact, faster loading).

#### `load(Str $filename) --> DAWG`
Class method that loads a DAWG from a file (auto-detects format).

#### `load-json(Str $filename) --> DAWG`
Class method that loads a DAWG from a JSON file.

#### `load-json-compressed(Str $filename) --> DAWG`
Class method that loads a DAWG from JSON with automatic Unicode compression detection. Analyzes all characters in the JSON data values and applies compression if the total count of unique alphanumeric/special characters (a-zA-Z0-9#_@=<>!?) plus unique Unicode characters is ≤89. When compressed, each Unicode character is mapped to an unused single-byte slot for 75% space savings.

#### `load-binary(Str $filename) --> DAWG`
Class method that loads a DAWG from a binary file.

#### `stats() --> Hash`
Returns statistics about the DAWG:
- `nodes` - Number of nodes
- `edges` - Number of edges
- `minimized` - Whether the DAWG has been minimized
- `values` - Number of stored values
- `memory-bytes` - Estimated memory usage

#### `rebuild(Bool :$try-compress-unicode = False)`
Rebuilds the DAWG from its current content, resetting its type (ASCII-only, compressed Unicode 7-bit, or UTF-32). If `:try-compress-unicode` is True, analyzes the content and applies compression if beneficial (≤89 unique characters).
#### `is-ascii-only() --> Bool`
Returns True if the DAWG contains only ASCII characters.

#### `is-compressed-unicode() --> Bool`
Returns True if the DAWG is using compressed Unicode (7-bit) encoding mode.

#### `loaded-as-ascii() --> Bool`
Returns True if the DAWG was loaded from an ASCII-optimized binary file.

### DAWG::MMap Methods

#### `load(Str $filename) --> DAWG::MMap`
Class method that loads a binary DAWG file using memory mapping.

#### `contains(Str $word) --> Bool`
Returns True if the word exists in the memory-mapped DAWG.

#### `lookup(Str $word) --> Hash`
Returns a hash with the word and its associated value, or Nil if not found.

#### `find-prefixes(Str $prefix) --> Array`
Returns an array of all words that start with the given prefix.

#### `close()`
Unmaps the file and closes the file descriptor. Also called automatically on object destruction.

## Performance

- **Lookup time**: O(m) where m is the length of the word
- **Prefix search**: O(p + n) where p is the prefix length and n is the number of results
- **Space complexity**: O(n) where n is the total number of characters, but with high sharing due to minimization
- **Build time**: O(n log n) for n words due to sorting

### Benchmarks

Results for a 5,000-word ASCII dictionary:

| Operation | Time/Size | Notes |
|-----------|-----------|-------|
| Build | 98ms | Adding 5,000 words |
| Minimize | 894ms | Reduces to 14,839 nodes |
| Binary save | 636ms | - |
| File size | 619 KB | Binary format |
| Binary load | 127ms | Traditional loading |
| Memory-map load | **3.9ms** | 32x faster than traditional |
| Lookup (traditional) | 18μs | Per word lookup |
| Lookup (memory-mapped) | 200μs | Per word lookup |

Results for Czech text with compression:

| Format | File Size | Notes |
|--------|-----------|-------|
| Compressed Unicode | ~600 KB | 5,000 words, 7-bit encoding |
| UTF-32 | ~2.4 MB | Same dataset, 4x larger |

**Key insights:**

- Memory-mapped loading is **32x faster** than traditional loading
- Binary format is compact and efficient
- Compressed Unicode provides **75% space savings** vs UTF-32
- Memory-mapped lookups have ~10x overhead but still sub-millisecond
- ASCII-only mode provides maximum compression for pure ASCII data

## Character Encoding and Storage

### ASCII Optimization

When saving to binary format, DAWG automatically detects if all data contains only 7-bit ASCII characters (0-127). If so, it uses a compact storage format that reduces edge storage from 4 bytes to 1 byte per character, resulting in approximately 75% space savings.

### Compressed Unicode Mode (7-bit)

For data with Unicode characters, DAWG can use compressed Unicode mode which maps all characters to 7-bit ASCII space. This creates a custom 7-bit encoding where Unicode characters are mapped to unused ASCII slots (a-zA-Z0-9#_@=<>!?). This works when your total unique character count is ≤ 89.

**Benefits:**
- Unicode text stored in 7-bit ASCII space (75% space savings vs UTF-32)
- Same efficiency as ASCII-only mode but supports Unicode
- Supports languages like Russian (33 letters), Greek (24 letters), etc.
- All operations remain transparent - no code changes needed

### Why UTF-32?

The standard DAWG format uses UTF-32 (4 bytes per character) for several important reasons:

1. **Fixed-width encoding**: Each character occupies exactly 4 bytes, enabling direct memory access without variable-length decoding
2. **Direct indexing**: Character positions can be calculated mathematically (position × 4), crucial for memory-mapped operations
3. **No surrogate pairs**: Unlike UTF-16, every Unicode codepoint is represented directly without encoding complexity
4. **Memory alignment**: 4-byte alignment is optimal for modern CPU architectures
5. **Simplicity**: No need for complex UTF-8 decoding or UTF-16 surrogate pair handling in tight loops

**While UTF-32 uses more space than variable-length encodings, this is mitigated by our optimization strategies which automatically enable ascii or compressed unicode mode, so utf-32 is rarely necessary.**

**Example:**

```raku
# Load with automatic Unicode compression detection
my $dawg = DAWG.load-json-compressed("russian-data.json");

if $dawg.is-compressed-unicode {
    say "Using compressed mode with {$dawg.unicode-map.elems} mapped chars";
}

# All operations work normally
$dawg.add("Привет");     # Automatically compressed
$dawg.contains("мир");   # Transparent lookup
```

### Automatic Type Management

The DAWG automatically handles type transitions:

- **ASCII → Compressed Unicode (7-bit)**: When you add Unicode to an ASCII-only DAWG and total characters ≤89, automatically applies 7-bit compression
- **ASCII → UTF-32**: When you add Unicode to an ASCII-only DAWG and total characters >89, rebuilds as UTF-32
- **Compressed Unicode (7-bit) → UTF-32**: When you add characters outside the compressed mapping, rebuilds to UTF-32 format
- **UTF-32 → Compressed Unicode (7-bit)**: When beneficial (≤89 unique characters with Unicode), automatically applies 7-bit compression

This means you can freely add any content without worrying about format restrictions - the DAWG adapts as needed.

### Working with Optimizations

```raku
# ASCII-only DAWG
my $ascii-dawg = DAWG.new;
$ascii-dawg.add("hello");
$ascii-dawg.minimize;
$ascii-dawg.save-binary("ascii.dawg.bin");  # Auto ASCII optimization

# Unicode compression
my $unicode-dawg = DAWG.load-json-compressed("data.json");  # Auto compression
say $unicode-dawg.stats;  # Shows compression status

# Adding words/values with validation
$dawg.add("word", "value");  # Validates character set automatically

# Automatic upgrades
my $ascii-dawg = DAWG.load-binary("ascii-only.dawg.bin");
$ascii-dawg.add("Привет");  # Automatically rebuilds to compressed Unicode (7-bit) if ≤89 chars!

# UTF-32 DAWG with auto-compression
my $dawg = DAWG.new;
$dawg.add("hello");
$dawg.add("Привет");  # If total chars ≤89, automatically compresses

# Manual rebuild with automatic encoding selection
$dawg.rebuild;  # Automatically chooses best encoding

# Force specific encoding
$dawg.rebuild(:encoding('utf32'));  # Force UTF-32
$dawg.rebuild(:encoding('compressed'));  # Force 7-bit compression
```

## How It Works

A DAWG is a data structure that combines the features of a trie with the space efficiency of a DFA (Deterministic Finite Automaton). It achieves this by:

1. Starting as a trie during construction
2. Identifying nodes with identical "right languages" (suffixes)
3. Merging these equivalent nodes during minimization

This results in a highly compressed structure that still maintains fast lookup times.

## Contributing

https://github.com/slavenskoj/raku-dawg

## Author

Danslav Slavenskoj

## Version History

See the [Changes](Changes) file for a detailed version history.

### Latest Changes

**v0.0.6 (2025-06-17)**
- Fixed package structure for proper zef installation
- Fixed serialization in dictionary example to use binary format
- Improved error handling for save/load operations

**v0.0.5 (2025-06-15)**
- Tested search function
- Added spell checking example script

## License

This library is licensed under the The Artistic License 2.0. See the [LICENSE](LICENSE) file for details.

## See Also

- [Examples](examples/) - Usage examples including spell checker
- [Wikipedia: Directed Acyclic Word Graph](https://en.wikipedia.org/wiki/Deterministic_acyclic_finite_state_automaton)
- [Original DAWG paper](https://dl.acm.org/doi/10.1145/375360.375365)

