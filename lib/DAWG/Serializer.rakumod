use v6.d;

unit class DAWG::Serializer;

use DAWG::Node;
use DAWG::Binary;
use JSON::Fast;

=begin pod

=head1 NAME

DAWG::Serializer - Serialization support for DAWG structures

=head1 DESCRIPTION

Provides methods to save and load DAWG structures to/from disk.
Currently uses JSON format for portability, but can be extended
to support binary formats for better performance.

=end pod

# Save a DAWG to file
method save-dawg($dawg, Str $filename) {
    my %data = self!serialize-dawg($dawg);
    $filename.IO.spurt(to-json(%data, :!pretty));
}

# Load a DAWG from file - returns data for DAWG to construct itself
method load-dawg-data(Str $filename) {
    my %data = from-json($filename.IO.slurp);
    return self!deserialize-dawg-data(%data);
}

# Convert DAWG to serializable structure
method !serialize-dawg($dawg) {
    my @nodes;
    my %node-map;
    my $node-id = 0;
    
    # First pass: assign IDs to all nodes
    self!assign-ids($dawg.root, %node-map, $node-id);
    
    # Collect all nodes in order
    my @all-nodes;
    self!collect-nodes($dawg.root, @all-nodes, {});
    
    # Second pass: serialize nodes
    for @all-nodes -> $node {
        my $id = %node-map{$node.WHERE};
        my %node-data = (
            id => $id,
            is-terminal => $node.is-terminal,
            value => $node.value,
            edges => {}
        );
        
        for $node.edges.kv -> $char, $child {
            %node-data<edges>{$char} = %node-map{$child.WHERE};
        }
        
        @nodes[$id] = %node-data;
    }
    
    return {
        version => '1.0',
        root-id => %node-map{$dawg.root.WHERE},
        nodes => @nodes,
        stats => $dawg.stats,
        value-map => $dawg.value-map
    };
}

# Assign unique IDs to all nodes
method !assign-ids(DAWG::Node $node, %map, $id is rw) {
    return if %map{$node.WHERE}:exists;
    
    %map{$node.WHERE} = $id++;
    
    for $node.edges.values -> $child {
        self!assign-ids($child, %map, $id);
    }
}

# Collect all nodes in traversal order
method !collect-nodes(DAWG::Node $node, @nodes, %visited) {
    return if %visited{$node.WHERE}:exists;
    
    %visited{$node.WHERE} = True;
    @nodes.push($node);
    
    for $node.edges.values -> $child {
        self!collect-nodes($child, @nodes, %visited);
    }
}

# Load raw data from JSON (for Unicode compression analysis)
method load-dawg-raw(Str $filename) {
    my $json = slurp $filename;
    my %data = from-json $json;
    
    # Extract words with their values
    my @words;
    
    # If data already has words array, use it directly
    if %data<words>:exists {
        @words = %data<words>.List;
        return {
            words => @words,
            value-map => %data<value-map> // {},
            stats => %data<stats> // {}
        };
    }
    
    my %nodes = %data<nodes>;
    
    # Traverse the DAWG to collect all words
    sub collect-words-from($node-id, $prefix = '') {
        my %node = %nodes{$node-id};
        
        if %node<is-terminal> {
            if %node<value>:exists && %node<value>.defined {
                @words.push: { word => $prefix, value => %node<value> };
            } else {
                @words.push: $prefix;
            }
        }
        
        for %node<edges>.kv -> $char, $child-id {
            collect-words-from($child-id, $prefix ~ $char);
        }
    }
    
    collect-words-from(%data<root-id>);
    
    return {
        words => @words,
        value-map => %data<value-map> // {},
        minimized => %data<stats><minimized> // False
    };
}

# Deserialize DAWG from data structure
method !deserialize-dawg-data(%data) {
    # Create all nodes first
    my @nodes = DAWG::Node.new xx %data<nodes>.elems;
    
    # Set node properties and build edges
    for %data<nodes>.kv -> $id, %node-data {
        my $node = @nodes[$id];
        $node.is-terminal = %node-data<is-terminal>;
        if %node-data<value>:exists && %node-data<value>.defined {
            $node.value = %node-data<value>;
        }
        
        for %node-data<edges>.kv -> $char, $child-id {
            $node.add-edge($char, @nodes[$child-id]);
        }
    }
    
    # Return data needed to reconstruct DAWG
    return {
        root => @nodes[%data<root-id>],
        node-count => %data<stats><nodes> // @nodes.elems,
        edge-count => %data<stats><edges> // 0,
        minimized => %data<stats><minimized> // True,
        value-map => %data<value-map> // {}
    };
}

# Binary serialization for better performance
method save-binary($dawg, Str $filename) {
    # Collect all nodes and assign indices
    my @nodes;
    my %node-index;
    my $index = 0;
    self!collect-nodes-with-index($dawg.root, @nodes, %node-index, $index);
    
    
    # Verify all nodes are indexed
    my $total-edges = 0;
    for @nodes -> $node-info {
        $total-edges += $node-info<node>.edges.elems;
    }
    
    # Check if all data is ASCII (only if not using compressed Unicode)
    my $ascii-only = !$dawg.is-compressed-unicode && self!is-ascii-only($dawg, @nodes);
    
    # Determine flags
    my $flags = 0;
    if $dawg.is-compressed-unicode {
        $flags +|= DAWG::Binary::COMPRESSED_UNICODE;
    } elsif $ascii-only {
        $flags +|= DAWG::Binary::ASCII_ONLY;
    }
    
    # Calculate offsets
    my $header-offset = 0;
    my $nodes-offset = DAWG::Binary::HEADER_SIZE;
    my $edges-offset = $nodes-offset + (@nodes.elems * DAWG::Binary::NODE_SIZE);
    
    # First pass: just assign edge offsets
    my $current-edge-offset = $edges-offset;
    for @nodes.kv -> $i, $node-info {
        my $node = $node-info<node>;
        $node-info<edges-offset> = $current-edge-offset;
        $current-edge-offset += $node.edges.elems * DAWG::Binary::EDGE_SIZE;
    }
    
    # Second pass: build edge table with proper indices
    my @all-edges;
    for @nodes.kv -> $i, $node-info {
        my $node = $node-info<node>;
        my @node-edges;
        for $node.edges.kv -> $char, $child {
            # Use same key format as in collect-nodes-with-index
            my $child-key = $child.id.defined ?? "id-{$child.id}" !! "where-{$child.WHERE}";
            my $target-index = %node-index{$child-key};
            if !$target-index.defined {
                die "Internal error: child node not indexed for character '$char'. Node collection may have failed.";
            }
            @node-edges.push: {
                char => $char.Str.ord,  # Ensure $char is stringified
                target => $target-index
            };
        }
        $node-info<edges> = @node-edges;
        @all-edges.append: @node-edges;
    }
    
    my $value-map-offset = $current-edge-offset;
    
    # Create header
    my $header = DAWG::Binary::Header.new(
        flags => $flags,
        node-count => @nodes.elems,
        edge-count => @all-edges.elems,
        root-node-offset => $nodes-offset,
        value-map-offset => $value-map-offset,
        value-map-count => $dawg.value-map.elems
    );
    
    # Open file for writing
    my $fh = open $filename, :w, :bin;
    
    # Write header
    $fh.write($header.pack);
    
    # Write nodes
    for @nodes -> $node-info {
        my $node = $node-info<node>;
        my $flags = 0;
        $flags +|= DAWG::Binary::IS_TERMINAL if $node.is-terminal;
        $flags +|= DAWG::Binary::HAS_VALUE if $node.value.defined;
        
        my $binary-node = DAWG::Binary::BinaryNode.new(
            flags => $flags,
            value-index => $node.value.defined ?? $node.value !! DAWG::Binary::NO_VALUE,
            edge-count => $node-info<edges>.elems,
            edges-offset => $node-info<edges-offset>
        );
        
        $fh.write($binary-node.pack);
    }
    
    # Write edges
    for @all-edges -> $edge {
        my $binary-edge = DAWG::Binary::BinaryEdge.new(
            char => $edge<char>,
            target-node-index => $edge<target>
        );
        
        $fh.write($binary-edge.pack(:ascii($ascii-only)));
    }
    
    # Write value map
    if $dawg.value-map.elems > 0 {
        # Write count
        my $count-buf = buf8.allocate(4);
        $count-buf.write-uint32(0, $dawg.value-map.elems, LittleEndian);
        $fh.write($count-buf);
        
        # Write value map as binary
        if $ascii-only {
            # Format for ASCII: [key_length:uint32][key:ascii][value_length:uint32][value:ascii]
            for $dawg.value-map.kv -> $k, $v {
                # Write key length and ASCII encoded key
                my @key-bytes = $k.encode('ascii').list;
                my $key-len-buf = buf8.allocate(4);
                $key-len-buf.write-uint32(0, @key-bytes.elems, LittleEndian);
                $fh.write($key-len-buf);
                $fh.write(buf8.new(@key-bytes));
                
                # Write value length and ASCII encoded value
                my $value-str = $v.Str;
                my @value-bytes = $value-str.encode('ascii').list;
                my $value-len-buf = buf8.allocate(4);
                $value-len-buf.write-uint32(0, @value-bytes.elems, LittleEndian);
                $fh.write($value-len-buf);
                $fh.write(buf8.new(@value-bytes));
            }
        } else {
            # Format for UTF-32: [key_length:uint32][key:utf32][value_length:uint32][value:utf32]
            for $dawg.value-map.kv -> $k, $v {
                # Write key length and UTF-32 encoded key
                my @key-codepoints = $k.comb.map(*.ord);
                my $key-len-buf = buf8.allocate(4);
                $key-len-buf.write-uint32(0, @key-codepoints.elems, LittleEndian);
                $fh.write($key-len-buf);
                
                # Write each codepoint as uint32
                for @key-codepoints -> $cp {
                    my $cp-buf = buf8.allocate(4);
                    $cp-buf.write-uint32(0, $cp, LittleEndian);
                    $fh.write($cp-buf);
                }
                
                # Write value length and UTF-32 encoded value
                my $value-str = $v.Str;
                my @value-codepoints = $value-str.comb.map(*.ord);
                my $value-len-buf = buf8.allocate(4);
                $value-len-buf.write-uint32(0, @value-codepoints.elems, LittleEndian);
                $fh.write($value-len-buf);
                
                for @value-codepoints -> $cp {
                    my $cp-buf = buf8.allocate(4);
                    $cp-buf.write-uint32(0, $cp, LittleEndian);
                    $fh.write($cp-buf);
                }
            }
        }
    }
    
    # Write Unicode map if using compressed Unicode
    if $dawg.is-compressed-unicode {
        # Write count of mappings
        my $count-buf = buf8.allocate(4);
        $count-buf.write-uint32(0, $dawg.unicode-map.elems, LittleEndian);
        $fh.write($count-buf);
        
        # Write each mapping as [unicode_char:uint32][mapped_char:uint8][padding:3bytes]
        for $dawg.unicode-map.kv -> $unicode-char, $mapped-char {
            my $map-buf = buf8.allocate(8);
            $map-buf.write-uint32(0, $unicode-char.ord, LittleEndian);
            $map-buf.write-uint8(4, $mapped-char.ord);
            # 3 bytes padding automatically zero
            $fh.write($map-buf);
        }
    }
    
    $fh.close;
}

# Helper to collect nodes with index assignment
method !collect-nodes-with-index($node, @nodes, %index, $current-index is rw, %visited = {}) {
    # Use node ID if available, otherwise WHERE
    my $node-key = $node.id.defined ?? "id-{$node.id}" !! "where-{$node.WHERE}";
    
    return if %visited{$node-key}:exists;
    %visited{$node-key} = True;
    
    %index{$node-key} = $current-index++;
    @nodes.push: { node => $node };
    
    for $node.edges.values -> $child {
        self!collect-nodes-with-index($child, @nodes, %index, $current-index, %visited);
    }
}

# Check if all characters in the DAWG are ASCII
method !is-ascii-only($dawg, @nodes) {
    # Check all edge characters
    for @nodes -> $node-info {
        my $node = $node-info<node>;
        for $node.edges.keys -> $char {
            return False if $char.ord > 127;
        }
    }
    
    # Check all values in value map
    for $dawg.value-map.kv -> $k, $v {
        # Check key
        for $k.comb -> $char {
            return False if $char.ord > 127;
        }
        # Check value if it's a string
        if $v ~~ Str {
            for $v.comb -> $char {
                return False if $char.ord > 127;
            }
        }
    }
    
    return True;
}

method load-binary-data(Str $filename) {
    my $fh = open $filename, :r, :bin;
    my $size = $filename.IO.s;
    my $buf = $fh.read($size);
    $fh.close;
    
    # Parse header
    my $header = DAWG::Binary::Header.new.unpack($buf.subbuf(0, DAWG::Binary::HEADER_SIZE));
    
    # Check flags
    my $ascii-only = ?($header.flags +& DAWG::Binary::ASCII_ONLY);
    my $compressed-unicode = ?($header.flags +& DAWG::Binary::COMPRESSED_UNICODE);
    
    # Create nodes array
    my @nodes;
    for ^$header.node-count -> $i {
        @nodes.push: DAWG::Node.new;
    }
    
    # Parse nodes and rebuild structure
    for ^$header.node-count -> $i {
        my $offset = $header.root-node-offset + ($i * DAWG::Binary::NODE_SIZE);
        my $binary-node = DAWG::Binary::BinaryNode.new.unpack($buf, $offset);
        
        my $node = @nodes[$i];
        $node.is-terminal = ?$binary-node.is-terminal;  # Convert to Bool
        $node.value = $binary-node.value-index if $binary-node.has-value;
        
        # Read edges
        for ^$binary-node.edge-count -> $j {
            my $edge-offset = $binary-node.edges-offset + ($j * DAWG::Binary::EDGE_SIZE);
            my $binary-edge = DAWG::Binary::BinaryEdge.new.unpack($buf, $edge-offset, :ascii($ascii-only));
            
            my $char = $binary-edge.char.chr;
            my $target = @nodes[$binary-edge.target-node-index];
            $node.add-edge($char, $target);
        }
    }
    
    # Read value map
    my %value-map;
    if $header.value-map-count > 0 {
        my $value-offset = $header.value-map-offset;
        my $count = $buf.read-uint32($value-offset, LittleEndian);
        
        # Read binary-encoded value map
        my $offset = $value-offset + 4;
        for ^$count {
            if $ascii-only {
                # Read ASCII-encoded key
                my $key-len = $buf.read-uint32($offset, LittleEndian);
                $offset += 4;
                
                my $key = $buf.subbuf($offset, $key-len).decode('ascii');
                $offset += $key-len;
                
                # Read ASCII-encoded value
                my $value-len = $buf.read-uint32($offset, LittleEndian);
                $offset += 4;
                
                my $value = $buf.subbuf($offset, $value-len).decode('ascii');
                $offset += $value-len;
                
                # Try to convert value to number if possible
                %value-map{$key} = $value ~~ /^ \d+ $/ ?? +$value !! $value;
            } else {
                # Read UTF-32 encoded key
                my $key-len = $buf.read-uint32($offset, LittleEndian);
                $offset += 4;
                
                my @key-chars;
                for ^$key-len {
                    @key-chars.push: $buf.read-uint32($offset, LittleEndian);
                    $offset += 4;
                }
                my $key = @key-chars.map(*.chr).join;
                
                # Read UTF-32 encoded value
                my $value-len = $buf.read-uint32($offset, LittleEndian);
                $offset += 4;
                
                my @value-chars;
                for ^$value-len {
                    @value-chars.push: $buf.read-uint32($offset, LittleEndian);
                    $offset += 4;
                }
                my $value = @value-chars.map(*.chr).join;
                
                # Try to convert value to number if possible
                %value-map{$key} = $value ~~ /^ \d+ $/ ?? +$value !! $value;
            }
        }
    }
    
    # Load Unicode map if compressed Unicode
    my %unicode-map;
    my %reverse-unicode-map;
    my $tr-from = '';
    my $tr-to = '';
    
    if $compressed-unicode {
        # Find where Unicode map starts (after value map)
        my $unicode-map-offset = $header.value-map-offset;
        if $header.value-map-count > 0 {
            # Skip past value map to find Unicode map
            # This is a bit tricky - we need to calculate where value map ends
            # For now, let's read from the end of the file
            my $map-count = $buf.read-uint32($size - 4 - ($buf.read-uint32($size - 4, LittleEndian) * 8), LittleEndian);
            my $map-offset = $size - 4 - ($map-count * 8);
            
            for ^$map-count {
                my $unicode-ord = $buf.read-uint32($map-offset, LittleEndian);
                my $mapped-ord = $buf.read-uint8($map-offset + 4);
                
                my $unicode-char = $unicode-ord.chr;
                my $mapped-char = $mapped-ord.chr;
                
                %unicode-map{$unicode-char} = $mapped-char;
                %reverse-unicode-map{$mapped-char} = $unicode-char;
                $tr-from ~= $unicode-char;
                $tr-to ~= $mapped-char;
                
                $map-offset += 8;
            }
        }
    }
    
    # Return data for DAWG reconstruction
    return {
        root => @nodes[0],
        node-count => $header.node-count,
        edge-count => $header.edge-count,
        minimized => True,
        value-map => %value-map,
        ascii-only => $ascii-only,
        compressed-unicode => $compressed-unicode,
        unicode-map => %unicode-map,
        reverse-unicode-map => %reverse-unicode-map,
        tr-from => $tr-from,
        tr-to => $tr-to
    };
}

=begin pod

=head1 METHODS

=head2 save-dawg($dawg, $filename)

Saves a DAWG to a file in JSON format.

=head2 load-dawg($filename)

Loads a DAWG from a file.

=head2 save-binary($dawg, $filename)

Saves a DAWG in binary format with UTF-32 encoding for efficient loading and memory mapping.

=head2 load-binary-data($filename)

Loads a DAWG from binary format and returns the data for reconstruction.

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the Artistic License 2.0.

=end pod