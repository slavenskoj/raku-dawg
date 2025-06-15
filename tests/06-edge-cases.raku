#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 16;

# Test 1: Empty strings and edge cases
{
    my $dawg = DAWG.new;
    
    # Empty string
    lives-ok { $dawg.add('', 'empty') }, 'Can add empty string';
    ok $dawg.contains(''), 'Contains empty string';
    is $dawg.lookup('')<value>, 'empty', 'Empty string value retrieved';
    
    # Single character
    $dawg.add('a', 1);
    $dawg.add('б', 2);  # Cyrillic
    
    is $dawg.lookup('a')<value>, 1, 'Single ASCII char';
    is $dawg.lookup('б')<value>, 2, 'Single Unicode char';
}

# Test 2: Very long words
{
    my $dawg = DAWG.new;
    
    my $long-word = 'a' x 1000;
    my $long-unicode = 'ф' x 500;
    
    lives-ok { $dawg.add($long-word, 'long') }, 'Can add very long word';
    lives-ok { $dawg.add($long-unicode, 'long-unicode') }, 'Can add long Unicode';
    
    ok $dawg.contains($long-word), 'Contains long word';
    ok $dawg.contains($long-unicode), 'Contains long Unicode';
}

# Test 3: Duplicate handling
{
    my $dawg = DAWG.new;
    
    $dawg.add('duplicate', 1);
    $dawg.add('duplicate', 2);  # Overwrite
    
    is $dawg.lookup('duplicate')<value>, 2, 'Duplicate overwrites value';
}

# Test 4: Special Unicode (emoji, etc.)
{
    my $dawg = DAWG.new;
    
    $dawg.add('😀', 'smile');
    $dawg.add('🚀', 'rocket');
    $dawg.add('👨‍👩‍👧‍👦', 'family');  # Complex emoji
    
    ok $dawg.contains('😀'), 'Contains emoji';
    is $dawg.lookup('🚀')<value>, 'rocket', 'Emoji value retrieved';
    ok $dawg.contains('👨‍👩‍👧‍👦'), 'Contains complex emoji';
}

# Test 5: Case sensitivity
{
    my $dawg = DAWG.new;
    
    $dawg.add('Hello', 1);
    $dawg.add('hello', 2);
    $dawg.add('HELLO', 3);
    
    is $dawg.lookup('Hello')<value>, 1, 'Case sensitive - Hello';
    is $dawg.lookup('hello')<value>, 2, 'Case sensitive - hello';
    is $dawg.lookup('HELLO')<value>, 3, 'Case sensitive - HELLO';
}

done-testing;