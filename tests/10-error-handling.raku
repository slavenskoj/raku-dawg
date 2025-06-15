#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 15;

# Test 1: Invalid inputs
{
    my $dawg = DAWG.new;
    
    # Test with undefined values
    lives-ok { $dawg.add('test', Nil) }, 'Can add with Nil value';
    lives-ok { $dawg.add('test2', Any) }, 'Can add with Any value';
    
    # Empty string
    lives-ok { $dawg.add('', 'empty') }, 'Can add empty string';
    ok $dawg.contains(''), 'Empty string is stored';
    
    # Very long key
    my $long-key = 'x' x 10000;
    lives-ok { $dawg.add($long-key, 'long') }, 'Can add very long key';
    ok $dawg.contains($long-key), 'Long key is stored';
}

# Test 2: Lookup edge cases
{
    my $dawg = DAWG.new;
    $dawg.add('exists', 42);
    
    # Non-existent key
    ok !$dawg.lookup('not-exists').defined, 'Lookup non-existent returns undefined';
    
    # Similar but different keys
    $dawg.add('test', 1);
    $dawg.add('tests', 2);
    $dawg.add('testing', 3);
    
    is $dawg.lookup('test')<value>, 1, 'Exact match for test';
    is $dawg.lookup('tests')<value>, 2, 'Exact match for tests';
    is $dawg.lookup('testing')<value>, 3, 'Exact match for testing';
    ok !$dawg.lookup('tes').defined, 'Partial match returns undefined';
}

# Test 3: Prefix search edge cases
{
    my $dawg = DAWG.new;
    
    # Empty DAWG
    is $dawg.find-prefixes('any').elems, 0, 'Empty DAWG returns no prefixes';
    
    # Add some words
    $dawg.add('prefix');
    $dawg.add('prefixes');
    $dawg.add('prefixing');
    $dawg.add('prepare');
    
    # Various prefix searches
    is $dawg.find-prefixes('prefix').elems, 3, 'Found 3 words with prefix "prefix"';
    is $dawg.find-prefixes('pre').elems, 4, 'Found 4 words with prefix "pre"';
    is $dawg.find-prefixes('z').elems, 0, 'No words with prefix "z"';
}

done-testing;