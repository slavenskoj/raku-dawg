#!/usr/bin/env raku

use lib 'lib';
use DAWG;
use DAWG::Search::Pattern;
use DAWG::Search::Fuzzy;

sub MAIN() {
    # Create and populate DAWG
    my $dawg = DAWG.new;
    
    # Add sample words
    my @words = <
        apple application apply applied
        banana band bandana bandwidth
        car card care careful
        cat catch catcher catching
        dog dodge
        hello help helpful world word work
    >;
    
    say "Building DAWG with {+@words} words...";
    for @words -> $word {
        $dawg.add($word);
    }
    $dawg.minimize;
    
    # Create search instances
    my $pattern-search = DAWG::Search::Pattern.new(:$dawg);
    my $fuzzy-search = DAWG::Search::Fuzzy.new(:$dawg);
    
    say "\n=== Pattern Search Examples ===";
    
    # Test various patterns
    my @patterns = (
        'a*' => 'Words starting with "a"',
        '*ing' => 'Words ending with "ing"',
        'c?r*' => 'Words matching c?r*',
        '?a*' => 'Words with "a" as second letter',
        'ba*a' => 'Words starting with "ba" and ending with "a"',
    );
    
    for @patterns -> $p {
        my ($pattern, $desc) = $p.key, $p.value;
        my @matches = $pattern-search.find($pattern);
        say "\n$pattern - $desc:";
        say "  ", @matches ?? @matches.join(', ') !! '(no matches)';
    }
    
    say "\n\n=== Fuzzy Search Examples ===";
    
    # Test fuzzy search
    my @misspellings = <aple banan wrld helpfull cathing>;
    
    for @misspellings -> $word {
        say "\nSearching for '$word':";
        
        # Try different distances
        for 1..2 -> $dist {
            my @matches = $fuzzy-search.search($word, :max-distance($dist));
            if @matches {
                say "  Distance ≤ $dist: ", @matches.map({ "{$_<word>} (d={$_<distance>})" }).join(', ');
            }
        }
    }
    
    say "\n\n=== Spell Check Example ===";
    
    # Test spell checking
    my @to-check = <apple aple wrold hello helo>;
    
    for @to-check -> $word {
        my @suggestions = $fuzzy-search.spell-check($word);
        if @suggestions {
            say "'$word' → suggestions: ", @suggestions.map({ $_<word> }).join(', ');
        } else {
            say "'$word' → correct";
        }
    }
    
    say "\n\n=== Closest Matches Example ===";
    
    # Find closest matches regardless of distance
    my $target = 'prog';
    say "Finding closest matches to '$target':";
    my @closest = $fuzzy-search.closest($target, :limit(5));
    for @closest -> $match {
        say "  {$match<word>} (distance: {$match<distance>})";
    }
    
    say "\n\n=== Combined Search Example ===";
    
    # Find words matching a pattern, then fuzzy search within those
    say "Finding words like 'aplication' that start with 'a':";
    
    # First, get all words starting with 'a'
    my @a-words = $pattern-search.find('a*');
    
    # Then fuzzy search against this subset
    my @fuzzy-matches;
    for @a-words -> $word {
        my $distance = $fuzzy-search.distance('aplication', $word);
        if $distance <= 2 {
            @fuzzy-matches.push: { :$word, :$distance };
        }
    }
    
    @fuzzy-matches = @fuzzy-matches.sort({ $^a<distance> <=> $^b<distance> });
    for @fuzzy-matches -> $match {
        say "  {$match<word>} (distance: {$match<distance>})";
    }
    
    say "\n✓ Search modules demonstration complete!";
}