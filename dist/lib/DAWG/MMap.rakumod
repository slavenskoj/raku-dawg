use v6.d;
use NativeCall;

unit class DAWG::MMap;

use DAWG::Binary;
use JSON::Fast;

=begin pod

=head1 NAME

DAWG::MMap - Memory-mapped DAWG for zero-copy loading

=head1 DESCRIPTION

Provides a memory-mapped implementation of DAWG that allows zero-copy loading
of binary DAWG files. The entire DAWG structure is accessed directly from the
memory-mapped file without any deserialization.

=head1 SYNOPSIS

    use DAWG::MMap;
    
    # Load a DAWG using memory mapping
    my $dawg = DAWG::MMap.load("dictionary.dawg.bin");
    
    # Use it like a regular DAWG
    say $dawg.contains("apple");
    say $dawg.lookup("apple");
    
    # Cleanup when done
    $dawg.close;

=end pod

# Constants for mmap
constant PROT_READ   = 0x1;
constant PROT_WRITE  = 0x2;
constant MAP_SHARED  = 0x1;
constant MAP_PRIVATE = 0x2;
constant MAP_FAILED  = Pointer.new(-1);

# Platform-specific constants
my constant $MAP_TYPE = $*KERNEL.name eq 'darwin' ?? 0x0002 !! 0x0001;  # MAP_PRIVATE

# Native functions
sub mmap(Pointer $addr, size_t $length, int32 $prot, int32 $flags, 
         int32 $fd, long $offset) returns Pointer is native { * }
sub munmap(Pointer $addr, size_t $length) returns int32 is native { * }

# File operations
sub open(Str $pathname, int32 $flags) returns int32 is native { * }
sub close(int32 $fd) returns int32 is native { * }

# Constants for open
constant O_RDONLY = 0x0000;

# Forward declaration
class MMapNode { ... }

has Pointer $.data;
has Int $.size;
has int32 $.fd;
has DAWG::Binary::Header $.header;
has Int $.node-count;
has Int $.edge-count;
has %.value-map;

method load(Str $filename) {
    # Open file
    my $fd = open($filename, O_RDONLY);
    die "Failed to open file: $filename" if $fd < 0;
    
    # Get file size
    my $size = $filename.IO.s;
    
    # Memory map the file
    my $data = mmap(Pointer, $size, PROT_READ, $MAP_TYPE, $fd, 0);
    die "Failed to memory map file" if $data == MAP_FAILED;
    
    # Create instance
    my $self = self.bless(
        data => $data,
        size => $size,
        fd => $fd
    );
    
    # Parse header
    $self!parse-header;
    
    return $self;
}

method !parse-header() {
    # Read header from mapped memory
    my $buf = CArray[uint8].new;
    $buf := nativecast(CArray[uint8], $!data);
    
    # Validate magic number
    my @magic = $buf[0..3];
    die "Invalid DAWG file format" unless @magic eqv [68, 65, 87, 71]; # "DAWG"
    
    # Read header fields
    my $flags = self!read-uint32(8);
    $!node-count = self!read-uint32(12);
    $!edge-count = self!read-uint32(16);
    
    # Check if data is ASCII-only
    my $ascii-only = ?($flags +& DAWG::Binary::ASCII_ONLY);
    
    # Load value map if present
    my $value-map-offset = self!read-uint32(24);
    my $value-map-count = self!read-uint32(28);
    
    if $value-map-count > 0 {
        self!load-value-map($value-map-offset, $value-map-count, :$ascii-only);
    }
    
    # Store ASCII flag for later use
    $!header = DAWG::Binary::Header.new(flags => $flags);
}

method !read-uint32(Int $offset) {
    my $buf = nativecast(CArray[uint8], $!data);
    return $buf[$offset] +
           ($buf[$offset + 1] +< 8) +
           ($buf[$offset + 2] +< 16) +
           ($buf[$offset + 3] +< 24);
}

method !read-uint8(Int $offset) {
    my $buf = nativecast(CArray[uint8], $!data);
    return $buf[$offset];
}

method !read-string-ascii(Int $offset, Int $length) {
    my $buf = nativecast(CArray[uint8], $!data);
    my @chars;
    for ^$length {
        @chars.push: $buf[$offset + $_].chr;
    }
    return @chars.join;
}

# Public method for MMapNode to access
method read-uint32-at(Int $offset) {
    self!read-uint32($offset);
}

method read-uint8-at(Int $offset) {
    self!read-uint8($offset);
}

# Public method for MMapNode to access ASCII flag
method is-ascii-only() {
    return ?($!header.flags +& DAWG::Binary::ASCII_ONLY);
}

method !load-value-map(Int $offset, Int $count, Bool :$ascii-only = False) {
    # Read binary-encoded value map
    my $current-offset = $offset + 4;  # Skip count field
    
    for ^$count {
        if $ascii-only {
            # Read ASCII-encoded key
            my $key-len = self!read-uint32($current-offset);
            $current-offset += 4;
            
            my $key = self!read-string-ascii($current-offset, $key-len);
            $current-offset += $key-len;
            
            # Read ASCII-encoded value
            my $value-len = self!read-uint32($current-offset);
            $current-offset += 4;
            
            my $value = self!read-string-ascii($current-offset, $value-len);
            $current-offset += $value-len;
            
            # Try to convert value to number if possible
            %!value-map{$key} = $value ~~ /^ \d+ $/ ?? +$value !! $value;
        } else {
            # Read UTF-32 encoded key
            my $key-len = self!read-uint32($current-offset);
            $current-offset += 4;
            
            # Read key (UTF-32)
            my @key-chars;
            for ^$key-len {
                @key-chars.push: self!read-uint32($current-offset).chr;
                $current-offset += 4;
            }
            my $key = @key-chars.join;
            
            # Read value length
            my $value-len = self!read-uint32($current-offset);
            $current-offset += 4;
            
            # Read value (UTF-32)
            my @value-chars;
            for ^$value-len {
                @value-chars.push: self!read-uint32($current-offset).chr;
                $current-offset += 4;
            }
            my $value = @value-chars.join;
            
            # Try to convert value to number if possible
            %!value-map{$key} = $value ~~ /^ \d+ $/ ?? +$value !! $value;
        }
    }
}

method !get-node(Int $index) {
    my $offset = DAWG::Binary::HEADER_SIZE + ($index * DAWG::Binary::NODE_SIZE);
    return MMapNode.new(dawg => self, offset => $offset);
}

# Public method for MMapNode to access
method get-node-at(Int $index) {
    self!get-node($index);
}

method contains(Str $word) {
    my $node = self!get-node(0);  # Root node
    
    for $word.comb -> $char {
        $node = $node.get-edge($char);
        return False unless $node;
    }
    
    return $node.is-terminal;
}

method lookup(Str $word) {
    my $node = self!get-node(0);  # Root node
    
    for $word.comb -> $char {
        $node = $node.get-edge($char);
        return Nil unless $node;
    }
    
    if $node.is-terminal {
        my %result = word => $word;
        if $node.has-value {
            my $value-index = $node.value-index;
            %result<value> = %!value-map{$value-index} if %!value-map{$value-index}:exists;
        }
        return %result;
    }
    
    return Nil;
}

method find-prefixes(Str $prefix) {
    my $node = self!get-node(0);  # Root node
    
    # Navigate to prefix
    for $prefix.comb -> $char {
        $node = $node.get-edge($char);
        return [] unless $node;
    }
    
    # Collect all words from this node
    my @words;
    self!collect-words-from($node, $prefix, @words);
    return @words;
}

method !collect-words-from($node, Str $prefix, @words) {
    @words.push: $prefix if $node.is-terminal;
    
    for $node.edges -> $edge {
        my $child = $edge.value;
        my $new-prefix = $prefix ~ $edge.key;
        self!collect-words-from($child, $new-prefix, @words);
    }
}

method close() {
    if $!data && $!size {
        munmap($!data, $!size);
    }
    if $!fd >= 0 {
        close($!fd);
    }
}

method DESTROY() {
    self.close;
}

# Memory-mapped node representation
class MMapNode {
    has DAWG::MMap $.dawg;
    has Int $.offset;
    
    method flags() {
        $!dawg.read-uint32-at($!offset);
    }
    
    method is-terminal() {
        self.flags +& DAWG::Binary::IS_TERMINAL;
    }
    
    method has-value() {
        self.flags +& DAWG::Binary::HAS_VALUE;
    }
    
    method value-index() {
        $!dawg.read-uint32-at($!offset + 4);
    }
    
    method edge-count() {
        $!dawg.read-uint32-at($!offset + 8);
    }
    
    method edges-offset() {
        $!dawg.read-uint32-at($!offset + 12);
    }
    
    method get-edge(Str $char) {
        my $char-code = $char.ord;
        my $edge-count = self.edge-count;
        my $edges-offset = self.edges-offset;
        my $ascii-only = $!dawg.is-ascii-only;
        
        # Linear search through edges (could be optimized with binary search)
        for ^$edge-count -> $i {
            my $edge-offset = $edges-offset + ($i * DAWG::Binary::EDGE_SIZE);
            my ($edge-char, $target-index);
            
            if $ascii-only {
                # Read ASCII-encoded edge
                $edge-char = $!dawg.read-uint8-at($edge-offset);
                $target-index = $!dawg.read-uint8-at($edge-offset + 1) +
                               ($!dawg.read-uint8-at($edge-offset + 2) +< 8) +
                               ($!dawg.read-uint8-at($edge-offset + 3) +< 16);
            } else {
                # Read UTF-32 encoded edge
                $edge-char = $!dawg.read-uint32-at($edge-offset);
                $target-index = $!dawg.read-uint32-at($edge-offset + 4);
            }
            
            if $edge-char == $char-code {
                return $!dawg.get-node-at($target-index);
            }
        }
        
        return Nil;
    }
    
    method edges() {
        my @edges;
        my $edge-count = self.edge-count;
        my $edges-offset = self.edges-offset;
        my $ascii-only = $!dawg.is-ascii-only;
        
        for ^$edge-count -> $i {
            my $edge-offset = $edges-offset + ($i * DAWG::Binary::EDGE_SIZE);
            my ($char-code, $target-index);
            
            if $ascii-only {
                # Read ASCII-encoded edge
                $char-code = $!dawg.read-uint8-at($edge-offset);
                $target-index = $!dawg.read-uint8-at($edge-offset + 1) +
                               ($!dawg.read-uint8-at($edge-offset + 2) +< 8) +
                               ($!dawg.read-uint8-at($edge-offset + 3) +< 16);
            } else {
                # Read UTF-32 encoded edge
                $char-code = $!dawg.read-uint32-at($edge-offset);
                $target-index = $!dawg.read-uint32-at($edge-offset + 4);
            }
            
            @edges.push: (
                $char-code.chr => $!dawg.get-node-at($target-index)
            );
        }
        
        return @edges;
    }
}

=begin pod

=head1 METHODS

=head2 load($filename)

Load a binary DAWG file using memory mapping. Returns a new DAWG::MMap instance.

=head2 contains($word)

Check if a word exists in the DAWG.

=head2 lookup($word)

Look up a word and return its information including any associated value.

=head2 find-prefixes($prefix)

Find all words that start with the given prefix.

=head2 close()

Unmap the file and close the file descriptor. This is also called automatically
when the object is destroyed.

=head1 NOTES

This implementation provides true zero-copy access to DAWG data. The entire
data structure is accessed directly from the memory-mapped file without any
deserialization or copying.

For optimal performance, the binary format uses fixed-size structures that can
be directly accessed through pointer arithmetic.

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the Artistic License 2.0.

=end pod