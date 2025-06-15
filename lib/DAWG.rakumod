use v6.d;

=begin pod

=head1 NAME

DAWG - Directed Acyclic Word Graph implementation for Raku

=head1 SYNOPSIS

=begin code :lang<raku>
use DAWG;

# Create a new DAWG
my $dawg = DAWG.new;

# Add words with optional values
$dawg.add("apple", 1);
$dawg.add("application", 2);
$dawg.add("apply", 3);

# Build/minimize the DAWG
$dawg.minimize;

# Lookup operations
say $dawg.contains("apple");        # True
say $dawg.lookup("apple");          # { word => "apple", value => 1 }

# Prefix search
my @words = $dawg.find-prefixes("app");
# Returns: ["apple", "application", "apply"]

# Save and load
$dawg.save("my-dawg.dat");
my $loaded = DAWG.load("my-dawg.dat");
=end code

=head1 DESCRIPTION

DAWG (Directed Acyclic Word Graph) is a space-efficient data structure for storing
a set of strings, such as a dictionary. It combines the features of a trie with
the space efficiency of a minimal DFA (Deterministic Finite Automaton).

This implementation provides:

=item Fast lookup (O(m) where m is the length of the string)
=item Space-efficient storage
=item Prefix search capability
=item Optional value storage for each word
=item Serialization support

=head1 AUTHOR

Danslav Slavenskoj

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Danslav Slavenskoj

This library is licensed under the Artistic License 2.0.

=end pod

unit class DAWG;

use DAWG::Node;
use DAWG::Builder;
use DAWG::Serializer;

has DAWG::Node $.root is rw;
has Int $.node-count is rw = 0;
has Int $.edge-count is rw = 0;
has Bool $.minimized is rw = False;
has %.value-map is rw;
has Bool $.is-ascii-only is rw = True;  # Track if DAWG contains only ASCII
has Bool $.loaded-as-ascii is rw = False;  # Track if loaded from ASCII-optimized file
has Bool $.is-compressed-unicode is rw = False;  # Track if using compressed Unicode mode
has %.unicode-map;  # Map from Unicode char to a-zA-Z0-9
has %.reverse-unicode-map;  # Map from a-zA-Z0-9 to Unicode char
has Str $.tr-from is rw;  # String for tr// translation (Unicode chars)
has Str $.tr-to is rw;    # String for tr// translation (a-zA-Z0-9)
has Bool $.in-rebuild is rw = False;  # Prevent recursive rebuilds
has %.node-by-id is rw;  # Map from node ID to node for O(1) lookup
has Int $.next-node-id is rw = 0;  # Counter for assigning node IDs

submethod BUILD() {
    $!root = DAWG::Node.new;
    $!root.id = $!next-node-id++;
    %!node-by-id{$!root.id} = $!root;
    $!node-count = 1;
}

# Add a word to the DAWG
multi method add(Str $word) {
    self.add-word($word, Nil);
}

multi method add(Str $word, $value) {
    self.add-word($word, $value);
}

method add-word(Str $word, $value) {
    # If minimized, rebuild to allow additions
    if $!minimized {
        self.rebuild(:encoding('auto'), :!preserve-minimized);
    }
    
    # First check if we need to upgrade the DAWG type
    my $needs-upgrade = False;
    my $upgrade-reason = '';
    
    # Check word for upgrade needs
    if $!loaded-as-ascii {
        for $word.comb -> $char {
            if $char.ord > 127 {
                $needs-upgrade = True;
                $upgrade-reason = 'ASCII to Unicode';
                last;
            }
        }
        # Also check value if it's a string
        if !$needs-upgrade && $value.defined && $value ~~ Str {
            for $value.comb -> $char {
                if $char.ord > 127 {
                    $needs-upgrade = True;
                    $upgrade-reason = 'ASCII to Unicode';
                    last;
                }
            }
        }
    } elsif $!is-compressed-unicode {
        # Check if word has Unicode chars not in our mapping
        for $word.comb -> $char {
            if $char.ord > 127 && !(%!unicode-map{$char}:exists) {
                $needs-upgrade = True;
                $upgrade-reason = 'Compressed Unicode to standard';
                last;
            }
        }
        # Also check value if it's a string
        if !$needs-upgrade && $value.defined && $value ~~ Str {
            for $value.comb -> $char {
                if $char.ord > 127 && !(%!unicode-map{$char}:exists) {
                    $needs-upgrade = True;
                    $upgrade-reason = 'Compressed Unicode to standard';
                    last;
                }
            }
        }
    }
    
    # Perform upgrade if needed
    if $needs-upgrade {
        if $upgrade-reason eq 'ASCII to Unicode' {
            # For ASCII to Unicode upgrade, use auto mode to pick best encoding
            self.rebuild(:encoding('auto'));
        } else {
            # For compressed Unicode to standard, force UTF-32
            self.rebuild(:encoding('utf32'));
        }
        $!loaded-as-ascii = False;  # Clear the restriction
        # Re-add the word to the rebuilt DAWG
        return self.add-word($word, $value);
    }
    
    
    # Now proceed with normal add logic
    my $processed-word = $word;
    
    # Handle compressed Unicode mode
    if $!is-compressed-unicode {
        # Check if any mapping characters conflict
        my $has-conflict = False;
        for $word.comb -> $char {
            if ($char ~~ /<[a..zA..Z0..9!#$%&()*+,\-./:;<=>?@[\]^_{|}~]>/) && (%!reverse-unicode-map{$char}:exists) {
                $has-conflict = True;
                last;
            }
        }
        
        if $has-conflict {
            # Rebuild to UTF-32 due to mapping conflict
            self.rebuild(:encoding('utf32'));
            $!loaded-as-ascii = False;
            # Re-add the word to the rebuilt DAWG
            return self.add-word($word, $value);
        }
        
        # Compress the word
        $processed-word = self!compress-string($word);
    } elsif $!is-ascii-only {
        # Update ASCII-only status if we find non-ASCII characters
        for $word.comb -> $char {
            if $char.ord > 127 {
                $!is-ascii-only = False;
                last;
            }
        }
    }
    
    my $node = $!root;
    
    for $processed-word.comb -> $char {
        my $next = $node.get-edge($char);
        if !$next {
            $next = DAWG::Node.new;
            $next.id = $!next-node-id++;
            %!node-by-id{$next.id} = $next;
            $node.add-edge($char, $next);
            $!node-count++;
            $!edge-count++;
        }
        $node = $next;
    }
    
    $node.is-terminal = True;
    if $value.defined {
        # Values are stored in the value-map, not compressed
        # No need to validate characters in values
        
        $node.value = %!value-map.elems;
        %!value-map{$node.value} = $value;
        
        # Update ASCII-only status if we find non-ASCII characters
        if $!is-ascii-only && $value ~~ Str {
            for $value.comb -> $char {
                if $char.ord > 127 {
                    $!is-ascii-only = False;
                    last;
                }
            }
        }
    }
    
    # Check if we should apply compression after adding this word
    # Do this for non-compressed DAWGs that aren't restricted to ASCII and not in rebuild
    if !$!is-compressed-unicode && !$!loaded-as-ascii && !$!in-rebuild {
        # Check if this word has Unicode or if DAWG already has Unicode
        my $word-has-unicode = $word.comb.grep(*.ord > 127).so;
        my $value-has-unicode = $value.defined && $value ~~ Str && $value.comb.grep(*.ord > 127).so;
        my $has-unicode = !$!is-ascii-only || $word-has-unicode || $value-has-unicode;
        
        if $has-unicode {
            # Count all unique characters to see if compression would be beneficial
            my %all-chars;
            my @all-entries;
            self!collect-words($!root, '', @all-entries);
            
            for @all-entries -> $entry {
                for $entry<word>.comb -> $char {
                    %all-chars{$char}++;
                }
            }
            
            # If we have ≤89 unique characters, apply compression
            if %all-chars.elems <= 89 {
                self.rebuild(:encoding('compressed'));
                $!loaded-as-ascii = False;
            }
        }
    }
}


# Check if a word exists
method contains(Str $word) {
    my $result = self.lookup($word);
    return $result.defined;
}

# Lookup a word and return its value
method lookup(Str $word) {
    my $compressed-word = $!is-compressed-unicode ?? self!compress-string($word) !! $word;
    my $node = self!traverse($compressed-word);
    return Nil unless $node && $node.is-terminal;
    
    my %result = word => $word;
    if $node.value.defined {
        # Check both integer and string keys for compatibility
        if %!value-map{$node.value}:exists {
            %result<value> = %!value-map{$node.value};
        } elsif %!value-map{$node.value.Str}:exists {
            %result<value> = %!value-map{$node.value.Str};
        }
    }
    
    return %result;
}

# Find all words with a given prefix
method find-prefixes(Str $prefix) {
    my $compressed-prefix = $!is-compressed-unicode ?? self!compress-string($prefix) !! $prefix;
    my $node = self!traverse($compressed-prefix);
    return [] unless $node;
    
    my @results;
    self!collect-words($node, $compressed-prefix, @results);
    
    # Decompress words if needed
    if $!is-compressed-unicode {
        return @results.map({ self!decompress-string($_<word>) });
    } else {
        return @results.map({ $_<word> });
    }
}

# Get all words in the DAWG
method all-words() {
    my @results;
    self!collect-words($!root, '', @results);
    
    # Decompress words if needed
    if $!is-compressed-unicode {
        return @results.map({ self!decompress-string($_<word>) });
    } else {
        return @results.map({ $_<word> });
    }
}

# Minimize the DAWG
method minimize() {
    return if $!minimized;
    
    my $builder = DAWG::Builder.new(root => $!root);
    my ($new-root, $stats) = $builder.minimize;
    
    $!root = $new-root;
    $!node-count = $stats<nodes>;
    $!edge-count = $stats<edges>;
    $!minimized = True;
    
    # Rebuild the node-by-id mapping
    %!node-by-id = ();
    $!next-node-id = 0;
    self!rebuild-node-id-map($!root, SetHash.new);
    
    # Note: Subtree statistics need to be recomputed after minimization
    # since the node structure has changed
    
    say "DAWG minimized: $!node-count nodes, $!edge-count edges";
}

# Save to file (JSON format)
method save(Str $filename) {
    my $serializer = DAWG::Serializer.new;
    $serializer.save-dawg(self, $filename);
}

# Save to file (binary format)
method save-binary(Str $filename) {
    my $serializer = DAWG::Serializer.new;
    $serializer.save-binary(self, $filename);
}

# Load from file (class method, auto-detects format)
method load(Str $filename) {
    # Check if it's a binary file by reading magic number
    my $fh = open $filename, :r, :bin;
    my $magic = $fh.read(4);
    $fh.close;
    
    if $magic eqv buf8.new(68, 65, 87, 71) {  # "DAWG"
        return self.load-binary($filename);
    } else {
        return self.load-json($filename);
    }
}

# Load from JSON file
method load-json(Str $filename) {
    my $serializer = DAWG::Serializer.new;
    my %data = $serializer.load-dawg-data($filename);
    
    # Create new DAWG instance
    my $dawg = self.new;
    $dawg.root = %data<root>;
    $dawg.node-count = %data<node-count>;
    $dawg.edge-count = %data<edge-count>;
    $dawg.minimized = %data<minimized>;
    
    # Restore value map
    for %data<value-map>.kv -> $k, $v {
        $dawg.value-map{$k} = $v;
    }
    
    # Set flags based on loaded data
    if %data<compressed-unicode>:exists && %data<compressed-unicode> {
        $dawg.is-compressed-unicode = True;
        $dawg.unicode-map = %data<unicode-map>;
        $dawg.reverse-unicode-map = %data<reverse-unicode-map>;
        $dawg.tr-from = %data<tr-from>;
        $dawg.tr-to = %data<tr-to>;
        $dawg.is-ascii-only = False;
        $dawg.loaded-as-ascii = False;
    } elsif %data<ascii-only>:exists && %data<ascii-only> {
        $dawg.is-ascii-only = True;
        $dawg.loaded-as-ascii = True;
    }
    
    # Rebuild node ID mapping
    $dawg!rebuild-node-id-map($dawg.root, SetHash.new);
    
    return $dawg;
}

# Load from binary file
method load-binary(Str $filename) {
    my $serializer = DAWG::Serializer.new;
    my %data = $serializer.load-binary-data($filename);
    
    # Create new DAWG instance
    my $dawg = self.new;
    $dawg.root = %data<root>;
    $dawg.node-count = %data<node-count>;
    $dawg.edge-count = %data<edge-count>;
    $dawg.minimized = %data<minimized>;
    
    # Restore value map
    for %data<value-map>.kv -> $k, $v {
        $dawg.value-map{$k} = $v;
    }
    
    # Set flags based on loaded data
    if %data<compressed-unicode>:exists && %data<compressed-unicode> {
        $dawg.is-compressed-unicode = True;
        $dawg.unicode-map = %data<unicode-map>;
        $dawg.reverse-unicode-map = %data<reverse-unicode-map>;
        $dawg.tr-from = %data<tr-from>;
        $dawg.tr-to = %data<tr-to>;
        $dawg.is-ascii-only = False;
        $dawg.loaded-as-ascii = False;
    } elsif %data<ascii-only>:exists && %data<ascii-only> {
        $dawg.is-ascii-only = True;
        $dawg.loaded-as-ascii = True;
    }
    
    # Rebuild node ID mapping
    $dawg!rebuild-node-id-map($dawg.root, SetHash.new);
    
    return $dawg;
}

# Analyze characters in data and setup Unicode compression if beneficial
method !analyze-and-setup-unicode-compression(@words) {
    # Count ALL unique characters (both ASCII and Unicode)
    my %all-char-count;
    my %unicode-char-count;
    my $has-unicode = False;
    
    for @words -> $word {
        for $word.comb -> $char {
            %all-char-count{$char}++;
            if $char.ord > 127 {
                $has-unicode = True;
                %unicode-char-count{$char}++;
            }
        }
    }
    
    # Also check value-map if it has strings
    for %!value-map.kv -> $k, $v {
        for $k.comb -> $char {
            %all-char-count{$char}++;
            if $char.ord > 127 {
                $has-unicode = True;
                %unicode-char-count{$char}++;
            }
        }
        if $v ~~ Str {
            for $v.comb -> $char {
                %all-char-count{$char}++;
                if $char.ord > 127 {
                    $has-unicode = True;
                    %unicode-char-count{$char}++;
                }
            }
        }
    }
    
    # Check if compression is beneficial
    # We need: 1) Some Unicode chars, 2) Total unique chars <= 62
    if !$has-unicode {
        return False;  # No Unicode, no need for compression
    }
    
    # Check if total unique characters exceeds our mapping capacity (89 chars)
    if %all-char-count.elems > 89 {
        return False;  # Too many unique characters for compression
    }
    
    # Find which mapping characters are NOT used in the data
    # Now includes: a-z, A-Z, 0-9, plus 27 special characters: !#$%&()*+,-./:;<=>?@[]^_{|}~
    my @all-mapping-chars = ('a'..'z', 'A'..'Z', '0'..'9', '!', '#', '$', '%', '&', '(', ')', '*', '+', ',', '-', '.', ':', ';', '<', '=', '>', '?', '@', '[', ']', '^', '_', '{', '|', '}', '~').flat;
    my @available-for-mapping;
    
    for @all-mapping-chars -> $char {
        if !(%all-char-count{$char}:exists) {
            @available-for-mapping.push: $char;
        }
    }
    
    # Count characters that need mapping (only Unicode chars, not ASCII)
    my @chars-to-map;
    for %all-char-count.keys.sort -> $char {
        if $char.ord > 127 {  # Only map Unicode characters
            @chars-to-map.push: $char;
        }
    }
    
    # Check if we have enough slots for mapping
    if @chars-to-map.elems > @available-for-mapping.elems {
        return False;  # Not enough free a-zA-Z0-9 slots for mapping
    }
    
    # Create bidirectional mappings
    %!unicode-map = ();
    %!reverse-unicode-map = ();
    $!tr-from = '';
    $!tr-to = '';
    
    # Map non-alphanumeric characters to available a-zA-Z0-9 slots
    for @chars-to-map.kv -> $idx, $char {
        my $mapped-char = @available-for-mapping[$idx];
        %!unicode-map{$char} = $mapped-char;
        %!reverse-unicode-map{$mapped-char} = $char;
        $!tr-from ~= $char;
        $!tr-to ~= $mapped-char;
    }
    
    $!is-compressed-unicode = True;
    $!is-ascii-only = False;  # It's not pure ASCII
    
    return True;
}

# Convert string using Unicode compression
method !compress-string(Str $str) {
    return $str unless $!is-compressed-unicode;
    
    # Use trans method for character translation
    return $str.trans(%!unicode-map);
}

# Convert string back from compressed form
method !decompress-string(Str $str) {
    return $str unless $!is-compressed-unicode;
    
    # Use trans method for character translation
    return $str.trans(%!reverse-unicode-map);
}

# Load from JSON with optional Unicode compression
method load-json-compressed(Str $filename) {
    # First load the raw data
    my $serializer = DAWG::Serializer.new;
    my %raw-data = $serializer.load-dawg-raw($filename);
    
    # Create new DAWG instance
    my $dawg = self.new;
    
    # Set value map before analysis
    if %raw-data<value-map>:exists {
        for %raw-data<value-map>.kv -> $k, $v {
            $dawg.value-map{$k} = $v;
        }
    }
    
    # Analyze characters and setup compression if beneficial
    my @words = (%raw-data<words> || []).flat;
    if $dawg!analyze-and-setup-unicode-compression(@words) {
        # Add compressed words
        for @words -> $word-data {
            if $word-data ~~ Hash && ($word-data<word>:exists) {
                my $word = $word-data<word>;
                my $value-index = $word-data<value>;
                # Look up the actual value from the value-map
                my $value = $dawg.value-map{$value-index} // $value-index;
                $dawg.add($word, $value);
            } else {
                # Just a word string
                $dawg.add(~$word-data);
            }
        }
    } else {
        # Add words normally
        for @words -> $word-data {
            if $word-data ~~ Hash && ($word-data<word>:exists) {
                my $word = $word-data<word>;
                my $value-index = $word-data<value>;
                # Look up the actual value from the value-map
                my $value = $dawg.value-map{$value-index} // $value-index;
                $dawg.add($word, $value);
            } else {
                # Just a word string
                $dawg.add(~$word-data);
            }
        }
    }
    
    # Minimize if it was minimized
    if %raw-data<minimized> {
        $dawg.minimize;
    }
    
    return $dawg;
}

# Get node by ID for direct traversal
method get-node-by-id(Int $id) {
    %!node-by-id{$id}
}

# Get root node ID
method root-id() {
    $!root.id
}

# Compute subtree statistics for all nodes
method compute-subtree-stats() {
    self!compute-stats-recursive($!root, 0, SetHash.new);
}

# Helper method to compute stats recursively
method !compute-stats-recursive(DAWG::Node $node, Int $depth, SetHash $visited) {
    return if $visited{$node.WHERE};
    $visited{$node.WHERE} = True;
    
    $node.depth = $depth;
    
    # Initialize stats
    $node.subtree-word-count = 0;
    $node.min-word-length = Int.new(2**31 - 1);  # Max Int value
    $node.max-word-length = 0;
    
    # If terminal, count this word
    if $node.is-terminal {
        $node.subtree-word-count = 1;
        $node.min-word-length = $depth;
        $node.max-word-length = $depth;
    }
    
    # Process children
    for $node.edges.values -> $child {
        self!compute-stats-recursive($child, $depth + 1, $visited);
        
        # Aggregate stats from children
        $node.subtree-word-count += $child.subtree-word-count;
        $node.min-word-length = min($node.min-word-length, $child.min-word-length);
        $node.max-word-length = max($node.max-word-length, $child.max-word-length);
    }
    
    # Handle nodes with no terminal descendants
    if $node.subtree-word-count == 0 {
        $node.min-word-length = 0;
        $node.max-word-length = 0;
    }
}

# These methods are public but should only be used by search modules
# Regular users should not need to call these directly
method decompress-string(Str $str) {
    return self!decompress-string($str);
}

method compress-string(Str $str) {
    return self!compress-string($str);
}

# Get statistics
method stats() {
    return {
        nodes => $!node-count,
        edges => $!edge-count,
        minimized => $!minimized,
        values => %!value-map.elems,
        memory-bytes => self!estimate-memory,
        is-ascii-only => $!is-ascii-only,
        is-compressed-unicode => $!is-compressed-unicode,
        unicode-chars => $!is-compressed-unicode ?? %!unicode-map.elems !! 0
    };
}

# Rebuild the DAWG, automatically choosing the best encoding
method rebuild(:$encoding = 'auto', :$preserve-minimized = True) {
    # Set rebuild flag to prevent recursive rebuilds
    $!in-rebuild = True;
    
    # Collect all words with their values
    my @entries;
    self!collect-words($!root, '', @entries);
    
    # Decompress words if currently compressed
    if $!is-compressed-unicode {
        for @entries -> $entry {
            $entry<word> = self!decompress-string($entry<word>);
            # Also decompress string values
            if $entry<value>:exists && $entry<value> ~~ Str {
                $entry<value> = self!decompress-string($entry<value>);
            }
        }
    }
    
    # Create new DAWG
    my $new-dawg = DAWG.new;
    # Clear the node-by-id mapping from construction since we'll rebuild it
    $new-dawg.node-by-id = ();
    
    # Analyze characters to determine best encoding
    my %all-char-count;
    my $has-unicode = False;
    my $is-pure-ascii = True;
    
    for @entries -> $entry {
        for $entry<word>.comb -> $char {
            %all-char-count{$char}++;
            if $char.ord > 127 {
                $has-unicode = True;
                $is-pure-ascii = False;
            }
        }
        if $entry<value>:exists && $entry<value> ~~ Str {
            for $entry<value>.comb -> $char {
                %all-char-count{$char}++;
                if $char.ord > 127 {
                    $has-unicode = True;
                    $is-pure-ascii = False;
                }
            }
        }
    }
    
    # Determine encoding based on analysis or explicit setting
    my $use-compression = False;
    
    given $encoding {
        when 'auto' {
            # Automatically choose best encoding
            if $is-pure-ascii {
                # Keep as ASCII-only
                $new-dawg.is-ascii-only = True;
            } elsif $has-unicode && %all-char-count.elems <= 89 {
                # Try compressed Unicode
                $use-compression = True;
            }
            # Otherwise use UTF-32 (default)
        }
        when 'ascii' {
            if !$is-pure-ascii {
                die "Cannot force ASCII encoding: data contains Unicode characters";
            }
            $new-dawg.is-ascii-only = True;
        }
        when 'compressed' | 'compressed-unicode' | '7bit' {
            if !$has-unicode {
                die "Cannot use compressed Unicode: data contains no Unicode characters";
            }
            if %all-char-count.elems > 89 {
                die "Cannot use compressed Unicode: too many unique characters ({%all-char-count.elems} > 89)";
            }
            $use-compression = True;
        }
        when 'utf32' | 'standard' {
            # Force UTF-32 (no special flags needed)
        }
        default {
            die "Unknown encoding: $encoding. Valid options: auto, ascii, compressed, utf32";
        }
    }
    
    # Apply compression if needed
    if $use-compression {
        # Find which mapping characters are NOT used in the data
        my @all-mapping-chars = ('a'..'z', 'A'..'Z', '0'..'9', '!', '#', '$', '%', '&', '(', ')', '*', '+', ',', '-', '.', ':', ';', '<', '=', '>', '?', '@', '[', ']', '^', '_', '{', '|', '}', '~').flat;
        my @available-for-mapping;
        
        for @all-mapping-chars -> $char {
            if !(%all-char-count{$char}:exists) {
                @available-for-mapping.push: $char;
            }
        }
        
        # Count characters that need mapping (only Unicode chars)
        my @chars-to-map;
        for %all-char-count.keys.sort -> $char {
            if $char.ord > 127 {
                @chars-to-map.push: $char;
            }
        }
        
        # Set up compression
        $new-dawg.is-compressed-unicode = True;
        
        # Create the mapping
        for @chars-to-map Z @available-for-mapping -> ($unicode, $ascii) {
            $new-dawg.unicode-map{$unicode} = $ascii;
            $new-dawg.reverse-unicode-map{$ascii} = $unicode;
        }
        
        # Create translation strings for trans()
        $new-dawg.tr-from = @chars-to-map.join;
        $new-dawg.tr-to = @available-for-mapping[0..^@chars-to-map.elems].join;
        
        # Set compression flags
        $new-dawg.is-compressed-unicode = True;
        $new-dawg.is-ascii-only = False;
    }
    
    # Add all entries to new DAWG
    # Set in-rebuild flag on new DAWG to prevent recursive compression checks
    $new-dawg.in-rebuild = True;
    
    for @entries -> $entry {
        if $entry<value>:exists {
            $new-dawg.add($entry<word>, $entry<value>);
        } else {
            $new-dawg.add($entry<word>);
        }
    }
    
    # Minimize if original was minimized and we want to preserve that state
    if $!minimized && $preserve-minimized {
        $new-dawg.minimize;
    }
    
    # Update self with new DAWG's data
    $!root = $new-dawg.root;
    $!node-count = $new-dawg.node-count;
    $!edge-count = $new-dawg.edge-count;
    $!minimized = $new-dawg.minimized;
    %!value-map = $new-dawg.value-map;
    $!is-ascii-only = $new-dawg.is-ascii-only;
    $!loaded-as-ascii = False;  # Reset since we rebuilt
    $!is-compressed-unicode = $new-dawg.is-compressed-unicode;
    %!unicode-map = $new-dawg.unicode-map;
    %!reverse-unicode-map = $new-dawg.reverse-unicode-map;
    $!tr-from = $new-dawg.tr-from;
    $!tr-to = $new-dawg.tr-to;
    
    # Clear rebuild flag
    $!in-rebuild = False;
    
    # Rebuild node ID mapping  
    %!node-by-id = ();
    $!next-node-id = 0;
    self!rebuild-node-id-map($!root, SetHash.new);
    
    return self;
}

# Private methods
method !traverse(Str $word) {
    my $node = $!root;
    
    for $word.comb -> $char {
        $node = $node.get-edge($char);
        return Nil unless $node;
    }
    
    return $node;
}

method !collect-words(DAWG::Node $node, Str $prefix, @results) {
    if $node.is-terminal {
        my %entry = word => $prefix;
        if $node.value.defined {
            if %!value-map{$node.value}:exists {
                %entry<value> = %!value-map{$node.value};
            }
        }
        @results.push: %entry;
    }
    
    for $node.edges.kv -> $char, $child {
        self!collect-words($child, $prefix ~ $char, @results);
    }
}

method !estimate-memory() {
    # Rough estimation: 
    # - Each node: 32 bytes base + edges
    # - Each edge: 16 bytes (char + pointer)
    my $node-size = 32;
    my $edge-size = 16;
    my $value-size = %!value-map.elems * 16;
    
    return $!node-count * $node-size + $!edge-count * $edge-size + $value-size;
}

method !rebuild-node-id-map(DAWG::Node $node, SetHash $visited) {
    return if $visited{$node.WHERE};
    $visited{$node.WHERE} = True;
    
    # If node doesn't have an ID, assign one
    if !$node.id.defined {
        $node.id = $!next-node-id++;
    }
    
    # Add to mapping
    %!node-by-id{$node.id} = $node;
    
    # Update next-node-id if needed
    $!next-node-id = max($!next-node-id, $node.id + 1);
    
    # Recurse to children
    for $node.edges.values -> $child {
        self!rebuild-node-id-map($child, $visited);
    }
}

=begin pod

=head1 METHODS

=head2 new()

Creates a new empty DAWG.

=head2 add(Str $word, $value?)

Adds a word to the DAWG with an optional associated value.

=head2 contains(Str $word)

Returns True if the word exists in the DAWG.

=head2 lookup(Str $word)

Returns a hash with the word and its associated value (if any), or Nil if not found.

=head2 find-prefixes(Str $prefix)

Returns an array of all words that start with the given prefix.

=head2 all-words()

Returns an array of all words in the DAWG.

=head2 minimize()

Minimizes the DAWG by merging equivalent nodes. This should be called after adding all words.

=head2 save(Str $filename)

Saves the DAWG to a file.

=head2 load(Str $filename)

Class method that loads a DAWG from a file.

=head2 stats()

Returns a hash with statistics about the DAWG.

=end pod