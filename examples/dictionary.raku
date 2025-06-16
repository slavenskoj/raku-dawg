#!/usr/bin/env raku

use lib '../lib';
use DAWG;

# Example: Building a dictionary with word frequencies

my $dict = DAWG.new;

# Add words with their frequencies
my %word-freq = (
    'the'     => 1000,
    'quick'   => 50,
    'brown'   => 75,
    'fox'     => 60,
    'jumps'   => 45,
    'over'    => 200,
    'lazy'    => 30,
    'dog'     => 80,
    'the'     => 1000,  # Duplicate will overwrite
    'jumped'  => 40,
    'quickly' => 35,
);

say "Building dictionary...";
for %word-freq.kv -> $word, $freq {
    $dict.add($word, $freq);
}

say "Added {%word-freq.elems} words";

# Minimize the structure
say "\nMinimizing...";
$dict.minimize;

# Show statistics
my %stats = $dict.stats;
say "\nDictionary statistics:";
say "  Nodes: %stats<nodes>";
say "  Edges: %stats<edges>";
say "  Memory: {(%stats<memory-bytes> / 1024).fmt('%.1f')} KB";

# Demonstrate lookups
say "\nLookup examples:";
for <the fox rabbit> -> $word {
    if my $result = $dict.lookup($word) {
        say "  '$word' found with frequency: $result<value>";
    } else {
        say "  '$word' not found";
    }
}

# Demonstrate prefix search
say "\nWords starting with 'qu':";
for $dict.find-prefixes('qu') -> $word {
    my $freq = $dict.lookup($word)<value>;
    say "  $word (freq: $freq)";
}

# Save the dictionary (using binary format instead of JSON)
say "\nSaving dictionary in binary format...";
$dict.save-binary('word-frequencies.dawg.bin');
say "Dictionary saved to word-frequencies.dawg.bin";

# Load and verify
say "\nLoading dictionary...";
my $loaded = DAWG.load('word-frequencies.dawg.bin');
say "Loaded {$loaded.all-words.elems} words";

# Demonstrate loaded dictionary works
say "\nVerifying loaded dictionary:";
for <the fox rabbit> -> $word {
    if my $result = $loaded.lookup($word) {
        say "  '$word' found with frequency: $result<value>";
    } else {
        say "  '$word' not found";
    }
}

# Cleanup
'word-frequencies.dawg.bin'.IO.unlink;