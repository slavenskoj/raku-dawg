use v6.d;

unit module DAWG::Binary;

=begin pod

=head1 NAME

DAWG::Binary - Binary serialization format for DAWG structures

=head1 DESCRIPTION

Defines the binary format for DAWG serialization that supports zero-copy loading
through memory mapping. The format is designed to be directly usable when mapped
into memory without any deserialization step.

=head1 BINARY FORMAT

The binary format consists of:

1. Header (64 bytes)
   - Magic number: "DAWG" (4 bytes)
   - Version: uint32 (4 bytes)
   - Flags: uint32 (4 bytes)
   - Node count: uint32 (4 bytes)
   - Edge count: uint32 (4 bytes)
   - Root node offset: uint32 (4 bytes)
   - Value map offset: uint32 (4 bytes)
   - Value map count: uint32 (4 bytes)
   - Reserved: 32 bytes

2. Node Table (variable size)
   - Each node is fixed size (32 bytes):
     - Flags: uint32 (bit 0: is_terminal, bit 1: has_value)
     - Value index: uint32 (index into value table, or 0xFFFFFFFF if no value)
     - Edge count: uint32
     - Edges offset: uint32 (offset to edge array)
     - Reserved: 16 bytes

3. Edge Table (variable size)
   - Each edge is 8 bytes:
     - Character: uint32 (Unicode codepoint)
     - Target node index: uint32

4. Value Map (variable size)
   - Count: uint32
   - Entries: array of (key_index: uint32, value_offset: uint32)
   - Value data: serialized values

=end pod

# Binary format constants
constant MAGIC = buf8.new(68, 65, 87, 71);  # "DAWG" in ASCII
constant VERSION = 1;
constant HEADER_SIZE = 64;
constant NODE_SIZE = 32;
constant EDGE_SIZE = 8;

# Flag bits
constant IS_TERMINAL = 0x01;
constant HAS_VALUE = 0x02;
constant ASCII_ONLY = 0x04;  # Indicates all data is 7-bit ASCII
constant COMPRESSED_UNICODE = 0x08;  # Indicates Unicode compression is used

# Special values
constant NO_VALUE = 0xFFFFFFFF;

class Header {
    has buf8 $.magic = MAGIC;
    has uint32 $.version = VERSION;
    has uint32 $.flags = 0;
    has uint32 $.node-count = 0;
    has uint32 $.edge-count = 0;
    has uint32 $.root-node-offset = 0;
    has uint32 $.value-map-offset = 0;
    has uint32 $.value-map-count = 0;
    has buf8 $.reserved = buf8.allocate(32);
    
    method pack() {
        my $buf = buf8.allocate(HEADER_SIZE);
        
        # Magic number (4 bytes)
        $buf.subbuf-rw(0, 4) = $!magic;
        
        # Version (4 bytes)
        $buf.write-uint32(4, $!version, LittleEndian);
        
        # Flags (4 bytes)
        $buf.write-uint32(8, $!flags, LittleEndian);
        
        # Node count (4 bytes)
        $buf.write-uint32(12, $!node-count, LittleEndian);
        
        # Edge count (4 bytes)
        $buf.write-uint32(16, $!edge-count, LittleEndian);
        
        # Root node offset (4 bytes)
        $buf.write-uint32(20, $!root-node-offset, LittleEndian);
        
        # Value map offset (4 bytes)
        $buf.write-uint32(24, $!value-map-offset, LittleEndian);
        
        # Value map count (4 bytes)
        $buf.write-uint32(28, $!value-map-count, LittleEndian);
        
        # Reserved (32 bytes)
        $buf.subbuf-rw(32, 32) = $!reserved;
        
        return $buf;
    }
    
    method unpack(buf8 $buf) {
        die "Invalid buffer size" unless $buf.elems >= HEADER_SIZE;
        
        # Check magic number
        my $magic = $buf.subbuf(0, 4);
        die "Invalid magic number" unless $magic eqv MAGIC;
        
        $!magic = $magic;
        $!version = $buf.read-uint32(4, LittleEndian);
        $!flags = $buf.read-uint32(8, LittleEndian);
        $!node-count = $buf.read-uint32(12, LittleEndian);
        $!edge-count = $buf.read-uint32(16, LittleEndian);
        $!root-node-offset = $buf.read-uint32(20, LittleEndian);
        $!value-map-offset = $buf.read-uint32(24, LittleEndian);
        $!value-map-count = $buf.read-uint32(28, LittleEndian);
        $!reserved = $buf.subbuf(32, 32);
        
        return self;
    }
}

class BinaryNode {
    has uint32 $.flags = 0;
    has uint32 $.value-index = NO_VALUE;
    has uint32 $.edge-count = 0;
    has uint32 $.edges-offset = 0;
    has buf8 $.reserved = buf8.allocate(16);
    
    method is-terminal() { $!flags +& IS_TERMINAL }
    method has-value() { $!flags +& HAS_VALUE }
    
    method pack() {
        my $buf = buf8.allocate(NODE_SIZE);
        
        $buf.write-uint32(0, $!flags, LittleEndian);
        $buf.write-uint32(4, $!value-index, LittleEndian);
        $buf.write-uint32(8, $!edge-count, LittleEndian);
        $buf.write-uint32(12, $!edges-offset, LittleEndian);
        $buf.subbuf-rw(16, 16) = $!reserved;
        
        return $buf;
    }
    
    method unpack(buf8 $buf, uint32 $offset = 0) {
        die "Invalid buffer size" unless $buf.elems >= $offset + NODE_SIZE;
        
        $!flags = $buf.read-uint32($offset + 0, LittleEndian);
        $!value-index = $buf.read-uint32($offset + 4, LittleEndian);
        $!edge-count = $buf.read-uint32($offset + 8, LittleEndian);
        $!edges-offset = $buf.read-uint32($offset + 12, LittleEndian);
        $!reserved = $buf.subbuf($offset + 16, 16);
        
        return self;
    }
}

class BinaryEdge {
    has uint32 $.char;
    has uint32 $.target-node-index;
    
    method pack(Bool :$ascii = False) {
        my $buf = buf8.allocate(EDGE_SIZE);
        
        if $ascii {
            # For ASCII mode, store char as uint8 and use remaining 3 bytes for target
            $buf.write-uint8(0, $!char);
            # Store target in next 3 bytes (supports up to 16M nodes)
            $buf.write-uint8(1, $!target-node-index +& 0xFF);
            $buf.write-uint8(2, ($!target-node-index +> 8) +& 0xFF);
            $buf.write-uint8(3, ($!target-node-index +> 16) +& 0xFF);
            $buf.write-uint32(4, 0, LittleEndian);  # Reserved
        } else {
            $buf.write-uint32(0, $!char, LittleEndian);
            $buf.write-uint32(4, $!target-node-index, LittleEndian);
        }
        
        return $buf;
    }
    
    method unpack(buf8 $buf, uint32 $offset = 0, Bool :$ascii = False) {
        die "Invalid buffer size" unless $buf.elems >= $offset + EDGE_SIZE;
        
        if $ascii {
            $!char = $buf.read-uint8($offset + 0);
            $!target-node-index = $buf.read-uint8($offset + 1) +
                                 ($buf.read-uint8($offset + 2) +< 8) +
                                 ($buf.read-uint8($offset + 3) +< 16);
        } else {
            $!char = $buf.read-uint32($offset + 0, LittleEndian);
            $!target-node-index = $buf.read-uint32($offset + 4, LittleEndian);
        }
        
        return self;
    }
}

# Export format info
sub binary-format-info() is export {
    return {
        magic => MAGIC,
        version => VERSION,
        header-size => HEADER_SIZE,
        node-size => NODE_SIZE,
        edge-size => EDGE_SIZE,
        flags => {
            is-terminal => IS_TERMINAL,
            has-value => HAS_VALUE,
        },
        no-value => NO_VALUE,
    };
}

=begin pod

=head1 USAGE

This module defines the binary format but does not implement the actual
serialization/deserialization. See L<DAWG::Serializer> for the implementation.

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the Artistic License 2.0.

=end pod