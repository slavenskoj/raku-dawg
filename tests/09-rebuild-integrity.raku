#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 16;

# Test 1: Data integrity through rebuilds
{
    my $dawg = DAWG.new;
    
    # Add initial data
    my %test-data = (
        'apple' => 1,
        'banana' => 2,
        'cherry' => 3,
        'яблоко' => 10,
        'банан' => 20,
        'вишня' => 30
    );
    
    for %test-data.kv -> $word, $value {
        $dawg.add($word, $value);
    }
    
    # Force rebuild to UTF-32
    $dawg.rebuild(:encoding('utf32'));
    
    # Verify all data preserved
    my $all-preserved = True;
    for %test-data.kv -> $word, $value {
        $all-preserved &&= $dawg.lookup($word)<value> == $value;
    }
    ok $all-preserved, 'All data preserved through UTF-32 rebuild';
    
    # Force rebuild to compressed
    $dawg.rebuild(:encoding('compressed'));
    
    # Verify again
    $all-preserved = True;
    for %test-data.kv -> $word, $value {
        $all-preserved &&= $dawg.lookup($word)<value> == $value;
    }
    ok $all-preserved, 'All data preserved through compressed rebuild';
}

# Test 2: Rebuild with complex values
{
    my $dawg = DAWG.new;
    
    # Add complex value types
    $dawg.add('array', [1, 2, 3]);
    $dawg.add('hash', { a => 1, b => 2 });
    $dawg.add('nested', { data => [1, { x => 'y' }, 3] });
    
    # Trigger rebuilds
    $dawg.add('тест', 'test');  # Trigger compression
    
    # Verify complex values preserved
    is-deeply $dawg.lookup('array')<value>, [1, 2, 3], 'Array preserved through rebuild';
    is-deeply $dawg.lookup('hash')<value>, { a => 1, b => 2 }, 'Hash preserved through rebuild';
    is-deeply $dawg.lookup('nested')<value>, { data => [1, { x => 'y' }, 3] }, 
              'Nested structure preserved';
}

# Test 3: Minimize after rebuild
{
    my $dawg = DAWG.new;
    
    # Add words with shared suffixes
    for <running jumping walking talking singing> -> $word {
        $dawg.add($word);
    }
    
    my $original-nodes = $dawg.node-count;
    $dawg.minimize;
    my $minimized-nodes = $dawg.node-count;
    
    ok $minimized-nodes < $original-nodes, 'Initial minimization reduces nodes';
    
    # Add Unicode after minimization - should trigger rebuild
    lives-ok { $dawg.add('бегать', 'run') }, 'Can add words after minimization';
    
    # Check that minimized flag was cleared by rebuild
    nok $dawg.minimized, 'Minimized flag cleared after rebuild';
    
    # Minimize again
    $dawg.minimize;
    
    ok $dawg.minimized, 'Can minimize after rebuild';
    ok $dawg.contains('running') && $dawg.contains('бегать'), 
       'All words preserved through minimize and rebuild';
}

# Test 4: Automatic upgrade cascade
{
    my $dawg = DAWG.new;
    
    # Start with numbers and ASCII
    for 1..10 -> $i {
        $dawg.add("number$i", $i);
    }
    ok $dawg.is-ascii-only, 'Started ASCII with numbers';
    
    # Add Cyrillic
    $dawg.add('число', 'number');
    ok $dawg.is-compressed-unicode, 'Upgraded to compressed';
    
    # Add many unique characters to force UTF-32
    # We need more than 89 unique chars total
    my @scripts = |('א'..'ת'), |('ア'..'ン'), |('一'..'十'), |('ㄱ'..'ㅎ');
    for @scripts.pick(100) -> $char {
        $dawg.add("x$char");
    }
    
    nok $dawg.is-compressed-unicode, 'Upgraded to UTF-32 with many scripts';
    is $dawg.lookup('number5')<value>, 5, 'Original data still accessible';
}

# Test 5: Edge case for 89-character boundary
{
    my $dawg = DAWG.new;
    
    # Add exactly 89 unique characters
    my @chars = |('a'..'z'), |('A'..'Z'), |('0'..'9'),
                '!', '#', '$', '%', '&', '(', ')', '*', '+', ',', 
                '-', '.', ':', ';', '<', '=', '>', '?', '@', '[', 
                ']', '^', '_', '{', '|', '}', '~';
                
    # Use only these characters
    for @chars -> $char {
        $dawg.add("x$char");
    }
    
    # Should stay in UTF-32 (not compressed) because we used all slots
    nok $dawg.is-compressed-unicode, 'At 89-char boundary stays UTF-32';
    
    # But if we had some Unicode chars that could use the mappings...
    my $dawg2 = DAWG.new;
    $dawg2.add('тест');  # Uses some slots
    
    # Add remaining available slots
    for @chars.head(85) -> $char {  # Leave some room
        $dawg2.add("y$char");
    }
    
    ok $dawg2.is-compressed-unicode, 'Under 89 unique allows compression';
}

done-testing;