use v6.d;

unit class DAWG::Search::Fuzzy;

use DAWG;
use DAWG::Node;

=begin pod

=head1 NAME

DAWG::Search::Fuzzy - Fuzzy search with edit distance for DAWG

=head1 SYNOPSIS

=begin code :lang<raku>
use DAWG;
use DAWG::Search::Fuzzy;

my $dawg = DAWG.new;
$dawg.add($_) for <apple application hello world>;
$dawg.minimize;

my $search = DAWG::Search::Fuzzy.new(:$dawg);

# Find words within edit distance
my @matches = $search.search('aple', :max-distance(1));
# Returns: [{word => 'apple', distance => 1}]

# Find closest matches
@matches = $search.closest('wrld', :limit(5));
# Returns up to 5 closest matches
=end code

=head1 DESCRIPTION

This module provides fuzzy search functionality for DAWG data structures
using Levenshtein distance (edit distance). It efficiently finds words
that are similar to a target word within a specified threshold.

The implementation uses dynamic programming with early termination to
efficiently prune branches that cannot lead to matches within the
distance threshold.

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the MIT License.

=end pod

has DAWG $.dawg is required;

# Search for words within edit distance
method search(Str $target, Int :$max-distance = 2) {
    my @results;
    
    # Handle compression if needed
    my $target-compressed = $!dawg.is-compressed-unicode 
        ?? $!dawg.compress-string($target) 
        !! $target;
    
    # Initialize first row of edit distance matrix
    my @current-row = 0..$target-compressed.chars;
    
    self!search-recursive($!dawg.root, '', $target-compressed, @current-row, @results, $max-distance);
    
    # Sort by distance, then alphabetically
    return @results.sort({ $^a<distance> <=> $^b<distance> || $^a<word> cmp $^b<word> });
}

method !search-recursive(DAWG::Node $node, Str $word, Str $target, @prev-row, @results, Int $max-distance) {
    my $word-length = $word.chars;
    my @current-row;
    @current-row[0] = $word-length;
    
    # Calculate edit distances for this row
    for 1..$target.chars -> $col {
        my $target-char = $target.substr($col - 1, 1);
        my $word-char = $word.substr($word-length - 1, 1) if $word-length > 0;
        
        my $cost = 0;
        if $word-length > 0 {
            $cost = $word-char eq $target-char ?? 0 !! 1;
        }
        
        # Calculate minimum of:
        # - deletion: @current-row[$col - 1] + 1
        # - insertion: @prev-row[$col] + 1  
        # - substitution: @prev-row[$col - 1] + cost
        @current-row[$col] = min(
            @current-row[$col - 1] + 1,
            @prev-row[$col] + 1,
            @prev-row[$col - 1] + $cost
        );
    }
    
    # If this is a terminal node and within distance threshold
    if $node.is-terminal {
        my $distance = @current-row[*-1];
        if $distance <= $max-distance {
            # Handle decompression if needed
            my $original-word = $!dawg.is-compressed-unicode 
                ?? $!dawg.decompress-string($word) 
                !! $word;
            @results.push({
                word => $original-word,
                distance => $distance
            });
        }
    }
    
    # Early termination: if minimum value in current row > max-distance
    if @current-row.min <= $max-distance {
        # Continue searching children
        for $node.edges.kv -> $char, $child {
            self!search-recursive($child, $word ~ $char, $target, @current-row, @results, $max-distance);
        }
    }
}

# Find the N closest matches
method closest(Str $target, Int :$limit = 10) {
    # Start with small distance and increase until we have enough results
    my @results;
    my $distance = 0;
    
    while @results.elems < $limit && $distance <= $target.chars {
        @results = self.search($target, :max-distance($distance));
        $distance++;
    }
    
    return @results[0..^$limit];
}

# Calculate exact Levenshtein distance between two strings
method distance(Str $s1, Str $s2) {
    my @d;
    my $len1 = $s1.chars;
    my $len2 = $s2.chars;
    
    for 0..$len1 -> $i {
        @d[$i][0] = $i;
    }
    for 0..$len2 -> $j {
        @d[0][$j] = $j;
    }
    
    for 1..$len1 -> $i {
        for 1..$len2 -> $j {
            my $cost = $s1.substr($i-1, 1) eq $s2.substr($j-1, 1) ?? 0 !! 1;
            @d[$i][$j] = min(
                @d[$i-1][$j] + 1,      # deletion
                @d[$i][$j-1] + 1,      # insertion
                @d[$i-1][$j-1] + $cost # substitution
            );
        }
    }
    
    return @d[$len1][$len2];
}

# Specialized search for spell checking
method spell-check(Str $word, Int :$max-suggestions = 5) {
    # First check if word exists
    return [] if $!dawg.contains($word);
    
    # Find suggestions
    my @suggestions = self.closest($word, :limit($max-suggestions));
    
    # Filter out suggestions that are too different
    @suggestions = @suggestions.grep({ $_<distance> <= ($word.chars / 3).ceiling });
    
    return @suggestions;
}

=begin pod

=head1 METHODS

=head2 new(DAWG :$dawg!)

Creates a new fuzzy search instance for the given DAWG.

=head2 search(Str $target, Int :$max-distance = 2)

Finds all words in the DAWG within the specified edit distance from the target.
Returns an array of hashes with 'word' and 'distance' keys, sorted by distance.

=head2 closest(Str $target, Int :$limit = 10)

Finds up to $limit closest matches to the target word, regardless of distance.
Useful when you always want suggestions even if they're not very close.

=head2 distance(Str $s1, Str $s2)

Calculates the exact Levenshtein distance between two strings.
This is a utility method that doesn't use the DAWG.

=head2 spell-check(Str $word, Int :$max-suggestions = 5)

Specialized method for spell checking. Returns an empty array if the word
exists in the DAWG, otherwise returns up to $max-suggestions alternatives.
Filters out suggestions that are too different (distance > length/3).

=end pod