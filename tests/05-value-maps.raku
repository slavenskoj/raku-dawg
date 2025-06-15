#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 16;

# Test 1: Basic value storage
{
    my $dawg = DAWG.new;
    
    $dawg.add('one', 1);
    $dawg.add('two', 2);
    $dawg.add('three', 3);
    $dawg.add('no-value');
    
    is $dawg.lookup('one')<value>, 1, 'Numeric value 1';
    is $dawg.lookup('two')<value>, 2, 'Numeric value 2';
    is $dawg.lookup('three')<value>, 3, 'Numeric value 3';
    ok !$dawg.lookup('no-value')<value>.defined, 'No value defined';
}

# Test 2: String values
{
    my $dawg = DAWG.new;
    
    $dawg.add('hello', 'world');
    $dawg.add('foo', 'bar');
    $dawg.add('unicode', 'значение');  # Russian "value"
    
    is $dawg.lookup('hello')<value>, 'world', 'String value';
    is $dawg.lookup('foo')<value>, 'bar', 'String value 2';
    is $dawg.lookup('unicode')<value>, 'значение', 'Unicode string value';
}

# Test 3: Mixed value types
{
    my $dawg = DAWG.new;
    
    $dawg.add('int', 42);
    $dawg.add('str', 'forty-two');
    $dawg.add('float', 3.14159);
    $dawg.add('bool', True);
    $dawg.add('array', [1, 2, 3]);
    $dawg.add('hash', { a => 1, b => 2 });
    
    is $dawg.lookup('int')<value>, 42, 'Integer value';
    is $dawg.lookup('str')<value>, 'forty-two', 'String value';
    is $dawg.lookup('float')<value>, 3.14159, 'Float value';
    is $dawg.lookup('bool')<value>, True, 'Boolean value';
    is-deeply $dawg.lookup('array')<value>, [1, 2, 3], 'Array value';
    is-deeply $dawg.lookup('hash')<value>, { a => 1, b => 2 }, 'Hash value';
}

# Test 4: Value map access
{
    my $dawg = DAWG.new;
    
    $dawg.add('a', 'alpha');
    $dawg.add('b', 'beta');
    $dawg.add('c', 'gamma');
    
    my %value-map = $dawg.value-map;
    is %value-map.elems, 3, 'Value map has 3 entries';
    ok %value-map.values.any eq 'alpha', 'Value map contains alpha';
    ok %value-map.values.any eq 'beta', 'Value map contains beta';
}

done-testing;