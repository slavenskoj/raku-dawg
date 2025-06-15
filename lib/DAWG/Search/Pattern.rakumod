use v6.d;

unit class DAWG::Search::Pattern;

use DAWG;
use DAWG::Node;

=begin pod

=head1 NAME

DAWG::Search::Pattern - Pattern matching with wildcards for DAWG

=head1 SYNOPSIS

=begin code :lang<raku>
use DAWG;
use DAWG::Search::Pattern;

my $dawg = DAWG.new;
$dawg.add($_) for <apple application apply car card care>;
$dawg.minimize;

my $search = DAWG::Search::Pattern.new(:$dawg);

# Find words matching patterns
my @matches = $search.find('a?p*');    # apple, apply, application
@matches = $search.find('car?');       # card, care
@matches = $search.find('*tion');      # application
=end code

=head1 DESCRIPTION

This module provides pattern matching functionality for DAWG data structures.
It supports the following wildcards:

=item C<?> - Matches exactly one character
=item C<*> - Matches zero or more characters

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the MIT License.

=end pod

has DAWG $.dawg is required;

# Find words matching pattern with wildcards (? = any char, * = any sequence)
method find(Str $pattern) {
    my @results;
    my %seen;
    self!find-recursive($!dawg.root, '', $pattern, 0, @results, %seen);
    
    # Decompress results if needed
    if $!dawg.is-compressed-unicode {
        @results = @results.map({ $!dawg.decompress-string($_) });
    }
    
    return @results.unique;
}

method !find-recursive(DAWG::Node $node, Str $word-so-far, Str $pattern, Int $pattern-pos, @results, %seen = {}) {
    # If we've consumed the entire pattern
    if $pattern-pos >= $pattern.chars {
        if $node.is-terminal {
            @results.push($word-so-far);
        }
        return;
    }
    
    my $pattern-char = $pattern.substr($pattern-pos, 1);
    
    # Handle wildcards
    if $pattern-char eq '?' {
        # Match any single character
        for $node.edges.kv -> $char, $child {
            self!find-recursive($child, $word-so-far ~ $char, $pattern, $pattern-pos + 1, @results, %seen);
        }
    } elsif $pattern-char eq '*' {
        # Match zero or more characters
        # First, try matching zero characters
        self!find-recursive($node, $word-so-far, $pattern, $pattern-pos + 1, @results, %seen);
        
        # Then try matching one or more characters
        for $node.edges.kv -> $char, $child {
            # Continue with * (match more chars)
            self!find-recursive($child, $word-so-far ~ $char, $pattern, $pattern-pos, @results, %seen);
            # Move past * (done matching)
            self!find-recursive($child, $word-so-far ~ $char, $pattern, $pattern-pos + 1, @results, %seen);
        }
    } else {
        # Match exact character
        # If DAWG uses compression and char is non-ASCII, compress it
        my $search-char = $pattern-char;
        if $!dawg.is-compressed-unicode && $pattern-char ~~ /<-[\x00..\x7F]>/ {
            $search-char = $!dawg.compress-string($pattern-char);
        }
        
        my $edge = $node.get-edge($search-char);
        if $edge {
            self!find-recursive($edge, $word-so-far ~ $search-char, $pattern, $pattern-pos + 1, @results, %seen);
        }
    }
}

# Extended pattern matching with character classes
method find-extended(Str $pattern) {
    # Future: Support [abc], [^abc], \d, \w, etc.
    die "Extended patterns not yet implemented";
}

=begin pod

=head1 METHODS

=head2 new(DAWG :$dawg!)

Creates a new pattern search instance for the given DAWG.

=head2 find(Str $pattern)

Finds all words in the DAWG matching the given pattern.

=head3 Pattern Syntax

=item C<a> - Matches the literal character 'a'
=item C<?> - Matches any single character
=item C<*> - Matches zero or more characters

=head3 Examples

=item C<app*> - Words starting with "app"
=item C<*ing> - Words ending with "ing"
=item C<c?t> - Three-letter words starting with 'c' and ending with 't'
=item C<*ou*> - Words containing "ou"

=head2 find-extended(Str $pattern)

(Not yet implemented) Will support extended pattern syntax including character classes.

=end pod