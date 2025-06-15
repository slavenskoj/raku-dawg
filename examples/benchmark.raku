#!/usr/bin/env raku

use lib '../lib';
use DAWG;

# Benchmark DAWG performance

sub generate-words(Int $count) {
    my @words;
    my @prefixes = <pre post anti sub super inter trans over under out>;
    my @roots = <fix play work run jump walk talk think feel know>;
    my @suffixes = <ing ed er est ly ness ment able ible ful less>;
    
    for ^$count {
        my $word = @roots.pick;
        $word = @prefixes.pick ~ $word if Bool.pick;
        $word = $word ~ @suffixes.pick if Bool.pick;
        @words.push: $word;
    }
    
    # Add some variations
    for ^($count / 2) {
        my $base = @words.pick;
        @words.push: $base ~ "s";
        @words.push: $base ~ "ing" if $base.chars < 10;
    }
    
    return @words.unique;
}

sub benchmark-dawg(@words) {
    say "Benchmarking with {@words.elems} unique words...";
    say "-" x 50;
    
    # Build benchmark
    my $dawg = DAWG.new;
    my $start = now;
    
    for @words.kv -> $idx, $word {
        $dawg.add($word, $idx);
    }
    
    my $build-time = now - $start;
    say "Build time: {$build-time.fmt('%.3f')} seconds";
    say "Words/second: {(@words.elems / $build-time).fmt('%.0f')}";
    
    # Minimize benchmark
    $start = now;
    $dawg.minimize;
    my $minimize-time = now - $start;
    say "Minimize time: {$minimize-time.fmt('%.3f')} seconds";
    
    # Stats
    my %stats = $dawg.stats;
    say "\nStructure stats:";
    say "  Nodes: %stats<nodes>";
    say "  Edges: %stats<edges>";
    say "  Memory: {(%stats<memory-bytes> / 1024).fmt('%.1f')} KB";
    say "  Bytes/word: {(%stats<memory-bytes> / @words.elems).fmt('%.1f')}";
    
    # Lookup benchmark
    my @test-words = @words.pick(1000);
    $start = now;
    my $found = 0;
    
    for @test-words -> $word {
        $found++ if $dawg.contains($word);
    }
    
    my $lookup-time = now - $start;
    say "\nLookup benchmark (1000 words):";
    say "  Total time: {$lookup-time.fmt('%.3f')} seconds";
    say "  Lookups/second: {(1000 / $lookup-time).fmt('%.0f')}";
    say "  Average: {($lookup-time * 1_000_000 / 1000).fmt('%.1f')} μs/lookup";
    
    # Prefix search benchmark
    my @prefixes = @words.pick(10).map(*.substr(0, 3));
    $start = now;
    my $total-results = 0;
    
    for @prefixes -> $prefix {
        my @results = $dawg.find-prefixes($prefix);
        $total-results += @results.elems;
    }
    
    my $prefix-time = now - $start;
    say "\nPrefix search benchmark (10 prefixes):";
    say "  Total time: {$prefix-time.fmt('%.3f')} seconds";
    say "  Total results: $total-results";
    say "  Average: {($prefix-time * 1000 / 10).fmt('%.1f')} ms/search";
    
    # Serialization benchmark
    my $temp-file = $*TMPDIR.add('benchmark.dawg');
    
    $start = now;
    $dawg.save($temp-file.Str);
    my $save-time = now - $start;
    my $file-size = $temp-file.s;
    
    say "\nSerialization:";
    say "  Save time: {$save-time.fmt('%.3f')} seconds";
    say "  File size: {($file-size / 1024).fmt('%.1f')} KB";
    
    $start = now;
    my $loaded = DAWG.load($temp-file.Str);
    my $load-time = now - $start;
    
    say "  Load time: {$load-time.fmt('%.3f')} seconds";
    
    # Cleanup
    $temp-file.unlink;
    
    return %stats;
}

# Run benchmarks with different sizes
for 1000, 10000, 50000 -> $size {
    say "\n" ~ "=" x 50;
    my @words = generate-words($size);
    benchmark-dawg(@words);
}

say "\n" ~ "=" x 50;
say "Benchmark complete!";