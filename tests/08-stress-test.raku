#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 11;

# Test 1: Rapid transitions between encoding modes
{
    my $dawg = DAWG.new;
    
    # Start ASCII
    $dawg.add('hello', 1);
    ok $dawg.is-ascii-only, 'Started as ASCII';
    
    # Add Unicode to trigger compression
    $dawg.add('привет', 2);
    ok $dawg.is-compressed-unicode, 'Compressed after Unicode';
    
    # Add many different Unicode to potentially trigger UTF-32
    for 1..50 -> $i {
        $dawg.add("test{('а'..'я').pick}{('α'..'ω').pick}{('ㄱ'..'ㅎ').pick}", $i);
    }
    
    # Check final state
    ok $dawg.contains('hello'), 'Original ASCII preserved through transitions';
    ok $dawg.contains('привет'), 'Original Unicode preserved through transitions';
}

# Test 2: Concurrent-like access patterns
{
    my $dawg = DAWG.new;
    my @words = <apple banana cherry date elderberry fig grape>;
    my @unicode = <яблоко банан вишня дата бузина инжир виноград>;
    
    # Interleave ASCII and Unicode additions
    for ^@words.elems -> $i {
        $dawg.add(@words[$i], "en:$i");
        $dawg.add(@unicode[$i], "ru:$i");
    }
    
    # Verify all lookups work
    my $all-found = True;
    for ^@words.elems -> $i {
        $all-found &&= $dawg.lookup(@words[$i])<value> eq "en:$i";
        $all-found &&= $dawg.lookup(@unicode[$i])<value> eq "ru:$i";
    }
    ok $all-found, 'All interleaved words found correctly';
}

# Test 3: Memory efficiency with duplicates
{
    my $dawg = DAWG.new;
    
    # Add same word multiple times with different values
    for 1..100 -> $i {
        $dawg.add('duplicate', $i);
    }
    
    # Should only have one entry
    is $dawg.lookup('duplicate')<value>, 100, 'Last duplicate value retained';
    is $dawg.all-words.elems, 1, 'Only one word stored despite duplicates';
}

# Test 4: Prefix explosion test
{
    my $dawg = DAWG.new;
    
    # Add words with common prefixes
    my @prefixes = <pre pro anti dis un re>;
    my @stems = <fix test duct form act move>;
    
    for @prefixes -> $prefix {
        for @stems -> $stem {
            $dawg.add($prefix ~ $stem);
        }
    }
    
    $dawg.minimize;
    
    # Should efficiently share prefixes
    ok $dawg.minimized, 'DAWG minimized with prefix sharing';
    ok $dawg.node-count < @prefixes.elems * @stems.elems * 5, 
       'Node count shows prefix sharing efficiency';
}

# Test 5: Unicode normalization edge cases
{
    my $dawg = DAWG.new;
    
    # Add composed and decomposed forms
    $dawg.add('café', 1);  # é as single character
    $dawg.add('café', 2);  # é as e + combining acute (if different)
    
    # Test other Unicode edge cases
    $dawg.add('𝓗𝓮𝓵𝓵𝓸', 'fancy');  # Mathematical bold script
    $dawg.add('🏴󠁧󠁢󠁳󠁣󠁴󠁿', 'scotland');  # Complex flag emoji
    $dawg.add('👨‍👩‍👧‍👦', 'family');  # Family emoji with ZWJ
    
    ok $dawg.contains('café'), 'Handles Unicode normalization';
    ok $dawg.contains('𝓗𝓮𝓵𝓵𝓸') && $dawg.contains('🏴󠁧󠁢󠁳󠁣󠁴󠁿'), 
       'Handles complex Unicode sequences';
}

done-testing;