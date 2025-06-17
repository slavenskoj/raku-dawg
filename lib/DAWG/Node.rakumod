use v6.d;

unit class DAWG::Node;

=begin pod

=head1 NAME

DAWG::Node - Node class for DAWG data structure

=head1 DESCRIPTION

Represents a single node in a DAWG (Directed Acyclic Word Graph).
Each node can have multiple outgoing edges (one per character) and
can be marked as terminal (end of a word).

=end pod

has %.edges;                    # Map of character -> Node
has Bool $.is-terminal is rw = False;
has Int $.value is rw;         # Optional value for terminal nodes
has Str $.signature is rw;     # For minimization
has Int $.id is rw;            # Unique node identifier
has Int $.subtree-word-count is rw = 0;  # Number of words in subtree
has Int $.min-word-length is rw;         # Minimum word length in subtree
has Int $.max-word-length is rw;         # Maximum word length in subtree
has Int $.depth is rw = 0;               # Distance from root

# Add an edge from this node
method add-edge(Str $char, DAWG::Node $node) {
    %!edges{$char} = $node;
}

# Get the node connected by the given character
method get-edge(Str $char) {
    %!edges{$char}
}

# Remove an edge
method remove-edge(Str $char) {
    %!edges{$char}:delete;
}

# Get all outgoing edges
method get-edges() {
    %!edges.clone
}

# Check if node has any edges
method has-edges() {
    %!edges.elems > 0
}

# Compute a signature for this node (used in minimization)
method compute-signature() {
    my @parts;
    
    # Include terminal status
    @parts.push: $.is-terminal ?? '1' !! '0';
    
    # Include value if present
    @parts.push: $.value.defined ?? $.value.Str !! '_';
    
    # Include edge information
    for %!edges.keys.sort -> $char {
        my $child = %!edges{$char};
        # Child signatures must be computed before parent
        die "Child node signature not computed! This is a bug in minimize()" unless $child.signature.defined;
        @parts.push: "$char:" ~ $child.signature;
    }
    
    $!signature = @parts.join('|');
}

# Create a deep copy of this node
method clone() {
    my $new-node = self.new(
        is-terminal => $!is-terminal,
        value => $!value
    );
    
    # Note: edges are not cloned here to avoid infinite recursion
    # The caller must handle edge cloning appropriately
    
    return $new-node;
}

# String representation for debugging
method gist() {
    my $terminal = $.is-terminal ?? '✓' !! '✗';
    my $val = $.value.defined ?? " (v:$.value)" !! '';
    my $edge-count = %!edges.elems;
    "Node[term:$terminal$val edges:$edge-count]"
}

=begin pod

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the Artistic License 2.0.

=end pod