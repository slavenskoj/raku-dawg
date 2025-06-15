#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 20;

# Test 1: Basic creation and operations
{
    my $dawg = DAWG.new;
    ok $dawg, 'DAWG created successfully';
    ok $dawg.is-ascii-only, 'New DAWG starts as ASCII-only';
    nok $dawg.is-compressed-unicode, 'New DAWG is not compressed';
}

# Test 2: Add and lookup ASCII words
{
    my $dawg = DAWG.new;
    
    $dawg.add('apple', 1);
    $dawg.add('application', 2);
    $dawg.add('apply', 3);
    
    ok $dawg.contains('apple'), 'Contains apple';
    ok $dawg.contains('application'), 'Contains application';
    ok $dawg.contains('apply'), 'Contains apply';
    nok $dawg.contains('app'), 'Does not contain app';
    
    is $dawg.lookup('apple')<value>, 1, 'Lookup apple returns 1';
    is $dawg.lookup('application')<value>, 2, 'Lookup application returns 2';
    is $dawg.lookup('apply')<value>, 3, 'Lookup apply returns 3';
    ok !$dawg.lookup('app').defined, 'Lookup non-existent returns undefined';
}

# Test 3: Prefix search
{
    my $dawg = DAWG.new;
    $dawg.add('apple');
    $dawg.add('application');
    $dawg.add('apply');
    $dawg.add('banana');
    
    my @app-words = $dawg.find-prefixes('app');
    is @app-words.elems, 3, 'Found 3 words with prefix app';
    ok 'apple' ∈ @app-words, 'apple in prefix results';
    ok 'application' ∈ @app-words, 'application in prefix results';
    ok 'apply' ∈ @app-words, 'apply in prefix results';
    nok 'banana' ∈ @app-words, 'banana not in prefix results';
}

# Test 4: Minimization
{
    my $dawg = DAWG.new;
    $dawg.add('car');
    $dawg.add('cars');
    $dawg.add('cat');
    $dawg.add('cats');
    
    my $nodes-before = $dawg.node-count;
    $dawg.minimize;
    my $nodes-after = $dawg.node-count;
    
    ok $dawg.minimized, 'DAWG is minimized';
    ok $nodes-after <= $nodes-before, 'Node count reduced or same after minimization';
    
    # Verify words still exist
    ok $dawg.contains('car') && $dawg.contains('cars') && 
       $dawg.contains('cat') && $dawg.contains('cats'), 
       'All words still exist after minimization';
       
    # Test that minimization reduces shared suffixes
    ok $dawg.edge-count < 12, 'Edge count reduced by suffix sharing';
}

done-testing;