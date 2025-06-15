#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 5;

# Test 1: Large dataset performance
{
    my $dawg = DAWG.new;
    my $start = now;
    
    # Add 10,000 words
    for ^10000 -> $i {
        $dawg.add("word$i", $i);
    }
    
    my $add-time = now - $start;
    ok $add-time < 10, "Added 10,000 words in under 10 seconds ({$add-time.fmt('%.2f')}s)";
    
    # Test lookup performance
    $start = now;
    for ^1000 -> $i {
        my $idx = (^10000).pick;
        $dawg.lookup("word$idx");
    }
    my $lookup-time = now - $start;
    ok $lookup-time < 1, "1000 lookups in under 1 second ({$lookup-time.fmt('%.2f')}s)";
    
    # Test minimization performance
    $start = now;
    $dawg.minimize;
    my $minimize-time = now - $start;
    ok $minimize-time < 5, "Minimized in under 5 seconds ({$minimize-time.fmt('%.2f')}s)";
}

# Test 2: Memory efficiency
{
    my $dawg = DAWG.new;
    
    # Add words with common prefixes (should share nodes)
    for <test testing tested tester tests> -> $word {
        $dawg.add($word);
    }
    
    $dawg.minimize;
    
    # These should share the 'test' prefix
    ok $dawg.node-count < 20, "Efficient node sharing ({$dawg.node-count} nodes)";
}

# Test 3: Unicode performance
{
    my $dawg = DAWG.new;
    my $start = now;
    
    # Add 1000 Unicode words
    for ^1000 -> $i {
        $dawg.add("тест$i", $i);
        $dawg.add("测试$i", $i);
    }
    
    my $unicode-time = now - $start;
    ok $unicode-time < 5, "Added 2000 Unicode words in under 5 seconds ({$unicode-time.fmt('%.2f')}s)";
}

done-testing;