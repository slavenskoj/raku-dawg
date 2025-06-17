use v6.d;

unit class DAWG::Builder;

use DAWG::Node;

has DAWG::Node $.root is required;
has %!registry;  # signature -> node mapping
has Int $.nodes-merged = 0;
has Int $.next-id = 0;  # For assigning new IDs during minimization
has %.id-map;  # Maps old node IDs to new node IDs

# Minimize the DAWG
method minimize() {
    # First, compute signatures for all nodes
    self!compute-all-signatures($!root, SetHash.new);
    
    # Then minimize by merging equivalent nodes
    my $new-root = self!minimize-node($!root, SetHash.new);
    
    # Count nodes and edges in the minimized DAWG
    my %stats = self!count-nodes-edges($new-root, SetHash.new);
    
    return ($new-root, %stats);
}

# Compute signatures for all nodes (post-order traversal)
method !compute-all-signatures(DAWG::Node $node, SetHash $visited) {
    return if $visited{$node.WHERE};
    $visited{$node.WHERE} = True;
    
    # First process all children
    for $node.edges.values -> $child {
        self!compute-all-signatures($child, $visited);
    }
    
    # Then compute this node's signature
    $node.compute-signature;
}

# Minimize a node and its subtree
method !minimize-node(DAWG::Node $node, SetHash $visited) {
    return $node if $visited{$node.WHERE};
    $visited{$node.WHERE} = True;
    
    # First minimize all children
    my %new-edges;
    for $node.edges.kv -> $char, $child {
        %new-edges{$char} = self!minimize-node($child, $visited);
    }
    
    # Create a new node with minimized children
    my $new-node = DAWG::Node.new(
        is-terminal => $node.is-terminal,
        value => $node.value
    );
    
    for %new-edges.kv -> $char, $child {
        $new-node.add-edge($char, $child);
    }
    
    # Compute signature for the new node
    $new-node.compute-signature;
    
    # Check if an equivalent node already exists
    if %!registry{$new-node.signature}:exists {
        $!nodes-merged++;
        # Map the old node's ID to the existing node's ID
        %!id-map{$node.id} = %!registry{$new-node.signature}.id if $node.id.defined;
        return %!registry{$new-node.signature};
    }
    
    # Assign a new ID to this node
    $new-node.id = $!next-id++;
    # Map the old node's ID to the new node's ID
    %!id-map{$node.id} = $new-node.id if $node.id.defined;
    
    # Register this node
    %!registry{$new-node.signature} = $new-node;
    return $new-node;
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