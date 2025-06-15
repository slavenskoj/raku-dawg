#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 17;

# Test 1: ASCII stays uncompressed
{
    my $dawg = DAWG.new;
    $dawg.add('hello', 1);
    $dawg.add('world', 2);
    
    ok $dawg.is-ascii-only, 'ASCII-only DAWG';
    nok $dawg.is-compressed-unicode, 'ASCII DAWG not compressed';
    is $dawg.lookup('hello')<value>, 1, 'ASCII lookup works';
}

# Test 2: Unicode triggers compression
{
    my $dawg = DAWG.new;
    $dawg.add('hello', 1);
    ok $dawg.is-ascii-only, 'Starts as ASCII';
    
    $dawg.add('привет', 2);  # Russian "hello"
    nok $dawg.is-ascii-only, 'No longer ASCII-only';
    ok $dawg.is-compressed-unicode, 'Automatically compressed';
    
    is $dawg.lookup('hello')<value>, 1, 'ASCII word preserved';
    is $dawg.lookup('привет')<value>, 2, 'Unicode word stored';
}

# Test 3: Direct Unicode also compresses
{
    my $dawg = DAWG.new;
    $dawg.add('привет', 1);
    $dawg.add('мир', 2);
    
    ok $dawg.is-compressed-unicode, 'Unicode-first DAWG compressed';
    is $dawg.lookup('привет')<value>, 1, 'First Unicode word';
    is $dawg.lookup('мир')<value>, 2, 'Second Unicode word';
}

# Test 4: Mixed content compresses correctly
{
    my $dawg = DAWG.new;
    $dawg.add('hello');
    $dawg.add('привет');
    $dawg.add('world');
    $dawg.add('мир');
    $dawg.add('test123');
    $dawg.add('тест456');
    
    ok $dawg.is-compressed-unicode, 'Mixed content compressed';
    ok $dawg.contains('hello') && $dawg.contains('привет'), 
       'Both ASCII and Unicode accessible';
    
    # Check prefix search works
    my @h-words = $dawg.find-prefixes('h');
    is @h-words.elems, 1, 'Found 1 word with prefix h';
    
    my @t-words = $dawg.find-prefixes('т');
    is @t-words.elems, 1, 'Found 1 word with prefix т';
}

# Test 5: Special characters work
{
    my $dawg = DAWG.new;
    $dawg.add('test!', 1);
    $dawg.add('hello@world', 2);
    $dawg.add('price:$99', 3);
    
    ok $dawg.is-ascii-only, 'Special ASCII chars keep DAWG ASCII-only';
    is $dawg.lookup('price:$99')<value>, 3, 'Special char lookup works';
}

done-testing;