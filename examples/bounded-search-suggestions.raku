#!/usr/bin/env raku

use lib '../lib';
use DAWG;

# Priority queue item for bounded search
class SearchNode {
    has Int $.node-id;
    has Str $.prefix;
    has Int $.distance;
    has Str $.target;
    
    # Calculate priority score (lower is better)
    method score() {
        # Combine edit distance with remaining string length
        $!distance + ($!target.chars - $!prefix.chars).abs
    }
}

# Calculate Levenshtein distance between two strings
sub levenshtein-distance(Str $s1, Str $s2) {
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

# Find suggestions using bounded search with node IDs
sub find-suggestions(DAWG $dawg, Str $target, Int :$max-distance = 2, Int :$max-results = 10) {
    my @results;
    my %visited;
    
    # Priority queue (using array with manual sorting for simplicity)
    my @queue;
    
    # Start from root
    @queue.push: SearchNode.new(
        node-id => $dawg.root-id,
        prefix => '',
        distance => 0,
        target => $target
    );
    
    while @queue && @results.elems < $max-results {
        # Sort by score and take best candidate
        @queue = @queue.sort(*.score);
        my $current = @queue.shift;
        
        # Skip if already visited this node with this prefix
        my $state-key = $current.node-id ~ ':' ~ $current.prefix;
        next if %visited{$state-key};
        %visited{$state-key} = True;
        
        # Early termination if distance exceeds threshold
        next if $current.distance > $max-distance;
        
        # Get the actual node using ID
        my $node = $dawg.get-node-by-id($current.node-id);
        next unless $node;
        
        # If this is a terminal node and within distance threshold
        if $node.is-terminal {
            my $final-distance = levenshtein-distance($current.prefix, $target);
            if $final-distance <= $max-distance {
                @results.push: {
                    word => $current.prefix,
                    distance => $final-distance,
                    score => $current.score
                };
            }
        }
        
        # Explore edges using node IDs
        for $node.edges.kv -> $char, $child {
            next unless $child.id.defined;
            
            my $new-prefix = $current.prefix ~ $char;
            
            # Calculate new distance (simple heuristic)
            my $new-distance = $current.distance;
            if $current.prefix.chars < $target.chars {
                my $target-char = $target.substr($current.prefix.chars, 1);
                $new-distance++ if $char ne $target-char;
            } else {
                $new-distance++;
            }
            
            # Only add to queue if potentially within bounds
            if $new-distance <= $max-distance {
                @queue.push: SearchNode.new(
                    node-id => $child.id,
                    prefix => $new-prefix,
                    distance => $new-distance,
                    target => $target
                );
            }
        }
        
        # Also consider skipping characters in target (deletion)
        if $current.prefix.chars < $target.chars {
            @queue.push: SearchNode.new(
                node-id => $current.node-id,
                prefix => $current.prefix,
                distance => $current.distance + 1,
                target => $target
            );
        }
    }
    
    # Sort results by distance, then alphabetically
    return @results.sort({ $^a<distance> <=> $^b<distance> || $^a<word> cmp $^b<word> });
}

# Example usage
sub MAIN() {
    # Create and populate DAWG
    my $dawg = DAWG.new;
    
    # Add sample words
    my @words = <
        apple application apply
        banana band bandana bandwidth
        cat catch catcher catching
        dog dodge
        elephant element elementary
        fish fishing fisherman
        hello help helpful
        world word work working
    >;
    
    say "Building DAWG with {+@words} words...";
    for @words -> $word {
        $dawg.add($word);
    }
    
    # Minimize for efficiency
    $dawg.minimize;
    my $stats = $dawg.stats;
    say "DAWG stats: {$stats<nodes>} nodes, {$stats<edges>} edges\n";
    
    # Test suggestions using node ID traversal
    my @test-words = <aple wrold helful elefant cathing>;
    
    for @test-words -> $misspelled {
        say "Suggestions for '$misspelled':";
        my @suggestions = find-suggestions($dawg, $misspelled, :max-distance(2), :max-results(5));
        
        for @suggestions -> $s {
            say "  {$s<word>} (distance: {$s<distance>})";
        }
        say "";
    }
    
    # Demonstrate direct node traversal
    say "Direct node traversal example:";
    say "Root node ID: {$dawg.root-id}";
    
    # Get 'a' node directly
    my $root = $dawg.get-node-by-id($dawg.root-id);
    my $a-node = $root.get-edge('a');
    if $a-node {
        say "'a' node ID: {$a-node.id}";
        
        # Jump directly to this node later
        my $direct-a = $dawg.get-node-by-id($a-node.id);
        say "Retrieved 'a' node directly: ", $direct-a.defined ?? "✓" !! "✗";
        
        # Count words starting with 'a'
        my $count = 0;
        sub count-terminals($node) {
            $count++ if $node.is-terminal;
            for $node.edges.values -> $child {
                count-terminals($child);
            }
        }
        count-terminals($direct-a);
        say "Words starting with 'a': $count";
    }
}