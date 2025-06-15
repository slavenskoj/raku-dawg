#!/usr/bin/env raku

use lib 'lib';
use DAWG;

# Example: Using node IDs for efficient DAWG traversal
sub MAIN() {
    # Create and populate DAWG
    my $dawg = DAWG.new;
    
    # Add sample words
    my @words = <
        car card care careful
        cat catch catcher
        dog dodge
        dot dote
    >;
    
    say "Building DAWG with {+@words} words...";
    for @words -> $word {
        $dawg.add($word);
    }
    $dawg.minimize;
    
    say "\n=== Node ID Traversal Demo ===\n";
    
    # 1. Direct node access by ID
    say "1. Direct Node Access:";
    my $root-id = $dawg.root-id;
    say "   Root node ID: $root-id";
    my $root = $dawg.get-node-by-id($root-id);
    say "   Root retrieved: ", $root.defined ?? "✓" !! "✗";
    
    # 2. Building a node ID map for a prefix
    say "\n2. Mapping prefix paths to node IDs:";
    my %prefix-to-node-id;
    
    sub map-prefixes($node, $prefix = '') {
        %prefix-to-node-id{$prefix} = $node.id;
        for $node.edges.kv -> $char, $child {
            map-prefixes($child, $prefix ~ $char);
        }
    }
    
    map-prefixes($root);
    
    # Show some mappings
    for <c ca car cat d do dog> -> $prefix {
        if %prefix-to-node-id{$prefix}:exists {
            say "   '$prefix' → node ID {%prefix-to-node-id{$prefix}}";
        }
    }
    
    # 3. Efficient subtree exploration using IDs
    say "\n3. Exploring subtrees via node IDs:";
    
    # Get the 'ca' node directly
    if %prefix-to-node-id<ca>:exists {
        my $ca-node-id = %prefix-to-node-id<ca>;
        my $ca-node = $dawg.get-node-by-id($ca-node-id);
        
        say "   Words starting with 'ca':";
        sub collect-words($node, $prefix) {
            my @words;
            @words.push($prefix) if $node.is-terminal;
            for $node.edges.kv -> $char, $child {
                @words.append: collect-words($child, $prefix ~ $char);
            }
            return @words;
        }
        
        for collect-words($ca-node, 'ca').sort -> $word {
            say "     - $word";
        }
    }
    
    # 4. Breadth-first search using node IDs
    say "\n4. BFS traversal using node ID queue:";
    
    my @queue = ($root-id => '');  # (node-id => prefix) pairs
    my @found-words;
    my $max-depth = 3;
    
    while @queue {
        my $pair = @queue.shift;
        my ($node-id, $prefix) = $pair.key, $pair.value;
        
        next if $prefix.chars > $max-depth;
        
        my $node = $dawg.get-node-by-id($node-id);
        next unless $node;
        
        @found-words.push($prefix) if $node.is-terminal && $prefix;
        
        # Add children to queue using their IDs
        for $node.edges.kv -> $char, $child {
            @queue.push: ($child.id => $prefix ~ $char);
        }
    }
    
    say "   Words with ≤ $max-depth characters:";
    for @found-words.sort -> $word {
        say "     - $word";
    }
    
    # 5. Node ID persistence check
    say "\n5. Node ID persistence:";
    
    # Store some node IDs
    my $c-node-id = %prefix-to-node-id<c>;
    my $dog-node-id = %prefix-to-node-id<dog>;
    
    # Access them directly
    my $c-node = $dawg.get-node-by-id($c-node-id);
    my $dog-node = $dawg.get-node-by-id($dog-node-id);
    
    say "   Node 'c' (ID: $c-node-id) is terminal: ", $c-node.is-terminal ?? "Yes" !! "No";
    say "   Node 'dog' (ID: $dog-node-id) is terminal: ", $dog-node.is-terminal ?? "Yes" !! "No";
    
    # 6. Efficient path checking using IDs
    say "\n6. Path validation using node IDs:";
    
    sub check-path(@chars) {
        my $current-id = $dawg.root-id;
        
        for @chars -> $char {
            my $node = $dawg.get-node-by-id($current-id);
            return False unless $node;
            
            my $next = $node.get-edge($char);
            return False unless $next;
            
            $current-id = $next.id;
        }
        
        my $final-node = $dawg.get-node-by-id($current-id);
        return $final-node.is-terminal;
    }
    
    for <car cart care dog dig> -> $word {
        my $exists = check-path($word.comb);
        say "   '$word' exists: ", $exists ?? "✓" !! "✗";
    }
    
    # Show final stats
    say "\n=== Statistics ===";
    my $stats = $dawg.stats;
    say "Nodes: {$stats<nodes>}";
    say "Edges: {$stats<edges>}";
    say "Node IDs in map: {$dawg.node-by-id.elems}";
}