#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 11;

# Test 1: Exactly 89 unique characters works
{
    my $dawg = DAWG.new;
    
    # Add all allowed mapping characters
    my @chars = |('a'..'z'), |('A'..'Z'), |('0'..'9'),
                '!', '#', '$', '%', '&', '(', ')', '*', '+', ',', 
                '-', '.', ':', ';', '<', '=', '>', '?', '@', '[', 
                ']', '^', '_', '{', '|', '}', '~';
    
    # Count special characters separately
    my $special-count = 27;  # The individual special characters
    my $letter-count = 26 + 26;  # a-z + A-Z
    my $digit-count = 10;  # 0-9
    is @chars.elems, $letter-count + $digit-count + $special-count, 'Have exactly 89 mapping characters';
    
    # Add some Unicode that will use these mappings
    $dawg.add('привет');  # Russian
    $dawg.add('мир');     # Russian
    
    ok $dawg.is-compressed-unicode, 'Can compress with Unicode';
    
    # This test actually adds too many unique chars, so it should fail compression
    for @chars.kv -> $i, $char {
        $dawg.add("test{$i}я{$char}");
    }
    
    # We've added digits in the test strings which weren't in original words
    # So we actually exceed 89 unique characters
    nok $dawg.is-compressed-unicode, 'Exceeds limit, switches to UTF-32';
}

# Test 2: Exceeding 89 unique characters triggers UTF-32
{
    my $dawg = DAWG.new;
    
    # Add some Unicode
    $dawg.add('привет');
    ok $dawg.is-compressed-unicode, 'Started compressed';
    
    # Add many different Unicode characters to exceed limit
    my @unicode-chars = <а б в г д е ё ж з и й к л м н о п р с т у ф х ц ч ш щ ъ ы ь э ю я>,
                       <А Б В Г Д Е Ё Ж З И Й К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Ъ Ы Ь Э Ю Я>,
                       <α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω>;
    
    for @unicode-chars -> $char {
        $dawg.add("test$char");
    }
    
    # With all these characters, we're likely over the limit
    nok $dawg.is-compressed-unicode, 'Exceeds limit with many Unicode chars';
    
    # Now add some Chinese characters that would push us over
    $dawg.add('你好世界');  # Chinese "hello world"
    $dawg.add('测试文本');  # Chinese "test text"
    
    # This should trigger UTF-32 if total unique > 89
    # Count unique characters
    my %all-chars;
    for $dawg.all-words -> $word {
        %all-chars{$_}++ for $word.comb;
    }
    
    if %all-chars.elems > 89 {
        nok $dawg.is-compressed-unicode, 'Switched to UTF-32 when exceeding limit';
    } else {
        ok $dawg.is-compressed-unicode, 'Still compressed (under limit)';
    }
    
    ok $dawg.contains('привет'), 'Original Unicode preserved';
    ok $dawg.contains('你好世界'), 'Chinese added successfully';
}

# Test 3: Mapping conflicts handled gracefully
{
    my $dawg = DAWG.new;
    
    # Add Unicode that will create mappings
    $dawg.add('тест');  # Will map т to something like 'a'
    ok $dawg.is-compressed-unicode, 'Compressed with Unicode';
    
    # Get the mapping for т
    my $t-mapping = $dawg.unicode-map<т> // 'unknown';
    diag "т maps to: $t-mapping";
    
    # Adding words with the mapping character is fine
    # (no conflict because we know which chars need reverse mapping)
    lives-ok { $dawg.add("test$t-mapping") }, 
             'Can add words with mapping characters';
    
    ok $dawg.contains('тест') && $dawg.contains("test$t-mapping"),
       'Both words coexist';
}

done-testing;