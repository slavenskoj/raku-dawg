use v6.d;

unit class DAWG::Builder;

use DAWG::Node;

has DAWG::Node $.root is required;
has %!registry;  # signature -> node mapping
has Int $.nodes-merged = 0;
has Int $.next-id = 0;  # For assigning new IDs during minimization
has %.id-map;  # Maps old node IDs to new node IDs
has %.node-cache;  # Cache to avoid recreating nodes

# Minimize the DAWG
method minimize() {
    # Reset state
    %!registry = ();
    %!node-cache = ();
    $!nodes-merged = 0;
    $!next-id = 0;
    %!id-map = ();
    
    # Assign unique IDs to all nodes first
    self!assign-all-ids($!root, SetHash.new);
    
    # Minimize the tree bottom-up
    my $new-root = self!minimize-recursive($!root, SetHash.new);
    
    # Count nodes and edges in the minimized DAWG
    my %stats = self!count-nodes-edges($new-root, SetHash.new);
    
    return ($new-root, %stats);
}

# Assign IDs to all nodes
method !assign-all-ids(DAWG::Node $node, SetHash $visited) {
    return if $visited{$node.WHERE};
    $visited{$node.WHERE} = True;
    
    $node.id = $!next-id++ unless $node.id.defined;
    
    for $node.edges.values -> $child {
        self!assign-all-ids($child, $visited);
    }
}

# Recursive minimization (bottom-up)
method !minimize-recursive(DAWG::Node $node, SetHash $visited) {
    # Use node ID as cache key instead of WHERE
    my $cache-key = $node.id;
    return %!node-cache{$cache-key} if %!node-cache{$cache-key}:exists;
    
    # Mark as visited to detect cycles
    $visited{$node.WHERE} = True;
    
    # First minimize all children
    my %minimized-edges;
    for $node.edges.kv -> $char, $child {
        # Skip if we're in a cycle
        if $visited{$child.WHERE} {
            # This is a cycle - just keep the reference for now
            %minimized-edges{$char} = $child;
        } else {
            %minimized-edges{$char} = self!minimize-recursive($child, $visited);
        }
    }
    
    # Create new node with minimized children
    my $new-node = DAWG::Node.new(
        is-terminal => $node.is-terminal,
        value => $node.value
    );
    
    # Add minimized edges
    for %minimized-edges.kv -> $char, $child {
        $new-node.add-edge($char, $child);
    }
    
    # Compute signature
    $new-node.compute-signature;
    
    # Check if equivalent node exists
    if %!registry{$new-node.signature}:exists {
        my $existing = %!registry{$new-node.signature};
        
        # Verify they're truly equivalent (not just same signature)
        if self!nodes-are-equivalent($new-node, $existing) {
            $!nodes-merged++;
            %!id-map{$node.id} = $existing.id if $existing.id.defined;
            %!node-cache{$cache-key} = $existing;
            $visited{$node.WHERE}:delete;  # Remove from visited
            return $existing;
        }
    }
    
    # Register new node
    $new-node.id = $!next-id++;
    %!id-map{$node.id} = $new-node.id;
    %!registry{$new-node.signature} = $new-node;
    %!node-cache{$cache-key} = $new-node;
    
    $visited{$node.WHERE}:delete;  # Remove from visited
    return $new-node;
}

# Check if two nodes are structurally equivalent
method !nodes-are-equivalent(DAWG::Node $a, DAWG::Node $b) {
    # Basic properties must match
    return False unless $a.is-terminal == $b.is-terminal;
    return False unless (!$a.value.defined && !$b.value.defined) ||
                       ($a.value.defined && $b.value.defined && $a.value == $b.value);
    
    # Must have same number of edges
    return False unless $a.edges.elems == $b.edges.elems;
    
    # All edges must match
    for $a.edges.kv -> $char, $child-a {
        return False unless $b.edges{$char}:exists;
        
        # For minimized nodes, we can compare by reference
        # since equivalent subtrees will be the same object
        my $child-b = $b.edges{$char};
        return False unless $child-a.WHERE == $child-b.WHERE;
    }
    
    return True;
}

# Count nodes and edges in the DAWG
method !count-nodes-edges(DAWG::Node $node, SetHash $visited) {
    my $nodes = 0;
    my $edges = 0;
    
    self!count-recursive($node, $visited, $nodes, $edges);
    
    return {
        nodes => $nodes,
        edges => $edges,
        merged => $!nodes-merged
    };
}

method !count-recursive(DAWG::Node $node, SetHash $visited, $nodes is rw, $edges is rw) {
    return if $visited{$node.WHERE};
    $visited{$node.WHERE} = True;
    
    $nodes++;
    $edges += $node.edges.elems;
    
    for $node.edges.values -> $child {
        self!count-recursive($child, $visited, $nodes, $edges);
    }
}

=begin pod

=head1 METHODS

=head2 new(root => $root-node)

Creates a new builder with the given root node.

=head2 minimize()

Minimizes the DAWG by merging equivalent nodes. Returns a tuple of
(new-root, stats) where stats is a hash containing node and edge counts.

=end pod