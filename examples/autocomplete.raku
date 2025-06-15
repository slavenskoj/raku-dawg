#!/usr/bin/env raku

use lib '../lib';
use DAWG;

# Example: Autocomplete system using DAWG

class Autocomplete {
    has DAWG $.dawg;
    has Int $.max-suggestions = 10;
    
    method new(@words, :$max-suggestions = 10) {
        my $dawg = DAWG.new;
        
        # Add words with popularity scores
        for @words.kv -> $idx, $word {
            # Simple scoring: earlier words are more popular
            my $score = @words.elems - $idx;
            $dawg.add($word, $score);
        }
        
        $dawg.minimize;
        
        self.bless(:$dawg, :$max-suggestions);
    }
    
    method suggest(Str $prefix) {
        my @matches = $!dawg.find-prefixes($prefix);
        return [] unless @matches;
        
        # Sort by score (popularity)
        my @scored;
        for @matches -> $word {
            my $result = $!dawg.lookup($word);
            my $score = $result ?? ($result<value> // 0) !! 0;
            @scored.push({ word => $word, score => $score });
        }
        @scored = @scored.sort({ $^b<score> <=> $^a<score> });
        
        # Return top suggestions
        return [] unless @scored;
        my $limit = min(@scored.elems, $!max-suggestions);
        my @top = @scored[^$limit];
        my @words;
        for @top -> $item {
            if $item ~~ Hash {
                @words.push($item<word>);
            }
        }
        return @words;
    }
}

# Example usage
my @programming-terms = <
    array algorithm application abstract
    binary buffer boolean branch
    class compile code constant cache
    data debug database declaration
    function framework file float
    integer interface implementation
    loop list library lambda
    method memory module macro
    object operator optimization
    pointer program parameter protocol
    string structure stack syntax
    variable vector value virtual
>;

say "Building autocomplete index...";
my $autocomplete = Autocomplete.new(@programming-terms, max-suggestions => 5);

say "\nAutocomplete demo:";
say "Type a prefix and press Enter (empty line to quit)";

loop {
    my $prefix = prompt("\n> ");
    last if !$prefix;
    
    my @suggestions = $autocomplete.suggest($prefix);
    
    if @suggestions {
        say "Suggestions for '$prefix':";
        for @suggestions.kv -> $idx, $word {
            say "  {$idx + 1}. $word";
        }
    } else {
        say "No suggestions found for '$prefix'";
    }
}