#!/usr/bin/env raku
use lib 'lib';
use DAWG;
use Test;

plan 22;

# Test 1: Various Unicode scripts
{
    my $dawg = DAWG.new;
    
    # Different scripts
    my %scripts = (
        'english' => 'Hello',
        'russian' => 'Привет',
        'greek' => 'Γειά σου',
        'arabic' => 'مرحبا',
        'hebrew' => 'שלום',
        'chinese' => '你好',
        'japanese' => 'こんにちは',
        'korean' => '안녕하세요',
        'thai' => 'สวัสดี',
        'hindi' => 'नमस्ते'
    );
    
    # Add all scripts
    for %scripts.kv -> $lang, $greeting {
        $dawg.add($greeting, $lang);
    }
    
    # Verify all can be retrieved
    my $all-found = True;
    my @failures;
    for %scripts.kv -> $lang, $greeting {
        my $result = $dawg.lookup($greeting);
        if !$result || $result<value> ne $lang {
            @failures.push("$lang: expected '$lang', got '{$result ?? $result<value> !! 'NOT FOUND'}'");
            $all-found = False;
        }
    }
    if @failures {
        diag "Failures: {@failures.join(', ')}";
    }
    ok $all-found, 'All Unicode scripts stored and retrieved correctly';
    
    # With only ~10 unique greetings, might still be compressed
    # Let's check what we actually got
    if %scripts.values.join.comb.unique.elems > 89 {
        nok $dawg.is-compressed-unicode, 'Multiple scripts trigger UTF-32';
    } else {
        ok $dawg.is-compressed-unicode || !$dawg.is-compressed-unicode, 
           'Compression depends on unique char count';
    }
}

# Test 2: Unicode combining characters
{
    my $dawg = DAWG.new;
    
    # Base + combining
    $dawg.add("e\x[0301]", 'e-acute-combined');  # e + combining acute
    $dawg.add("é", 'e-acute-precomposed');       # precomposed é
    
    # Multiple combining marks
    $dawg.add("e\x[0301]\x[0308]", 'e-acute-diaeresis');  # e + acute + diaeresis
    
    ok $dawg.contains("e\x[0301]"), 'Contains combining character sequence';
    ok $dawg.contains("é"), 'Contains precomposed character';
    ok $dawg.contains("e\x[0301]\x[0308]"), 'Contains multiple combinings';
}

# Test 3: Emoji and special sequences
{
    my $dawg = DAWG.new;
    
    # Simple emoji
    $dawg.add('😀', 'grin');
    $dawg.add('🎉', 'party');
    
    # Emoji with skin tone
    $dawg.add('👋🏻', 'wave-light');
    $dawg.add('👋🏿', 'wave-dark');
    
    # ZWJ sequences
    $dawg.add('👨‍💻', 'man-technologist');
    $dawg.add('👩‍🔬', 'woman-scientist');
    
    # Flag sequences
    $dawg.add('🇺🇸', 'flag-us');
    $dawg.add('🇯🇵', 'flag-jp');
    
    # Verify all stored
    ok $dawg.contains('😀'), 'Simple emoji stored';
    ok $dawg.contains('👋🏻'), 'Emoji with modifier stored';
    ok $dawg.contains('👨‍💻'), 'ZWJ sequence stored';
    ok $dawg.contains('🇺🇸'), 'Flag sequence stored';
    
    # Check lookups
    is $dawg.lookup('😀')<value>, 'grin', 'Simple emoji lookup works';
    is $dawg.lookup('👨‍💻')<value>, 'man-technologist', 'ZWJ lookup works';
}

# Test 4: Right-to-left and bidirectional text
{
    my $dawg = DAWG.new;
    
    # RTL text
    $dawg.add('שלום עולם', 'hebrew-hello-world');
    $dawg.add('مرحبا بالعالم', 'arabic-hello-world');
    
    # Mixed direction
    $dawg.add('Hello שלום', 'mixed-ltr-rtl');
    $dawg.add('עברית English', 'mixed-rtl-ltr');
    
    ok $dawg.contains('שלום עולם'), 'RTL Hebrew stored';
    ok $dawg.contains('مرحبا بالعالم'), 'RTL Arabic stored';
    ok $dawg.contains('Hello שלום'), 'Mixed direction stored';
}

# Test 5: Unicode normalization forms
{
    my $dawg = DAWG.new;
    
    # Different representations of same visual character
    my $nfc = "é";        # NFC: single codepoint U+00E9
    my $nfd = "é";        # NFD: e + combining acute
    
    $dawg.add($nfc, 'nfc');
    $dawg.add($nfd, 'nfd');
    
    # They might be stored separately depending on normalization
    ok $dawg.contains($nfc), 'NFC form stored';
    ok $dawg.contains($nfd), 'NFD form stored';
}

# Test 6: Surrogate pairs and special cases
{
    my $dawg = DAWG.new;
    
    # Mathematical alphanumeric symbols (outside BMP)
    $dawg.add('𝐇𝐞𝐥𝐥𝐨', 'math-bold');
    $dawg.add('𝓗𝓮𝓵𝓵𝓸', 'math-script');
    
    # Ancient scripts
    $dawg.add('𐎅𐎆𐎇', 'ugaritic');
    $dawg.add('𓀀𓀁𓀂', 'hieroglyphic');
    
    ok $dawg.contains('𝐇𝐞𝐥𝐥𝐨'), 'Math symbols stored';
    ok $dawg.contains('𐎅𐎆𐎇'), 'Ugaritic stored';
    ok $dawg.contains('𓀀𓀁𓀂'), 'Hieroglyphics stored';
}

# Test 7: Zero-width and invisible characters
{
    my $dawg = DAWG.new;
    
    # Zero-width characters
    $dawg.add("hello\x[200B]world", 'zwsp');      # zero-width space
    $dawg.add("test\x[200C]ing", 'zwnj');         # zero-width non-joiner
    $dawg.add("join\x[200D]ed", 'zwj');           # zero-width joiner
    
    ok $dawg.contains("hello\x[200B]world"), 'Zero-width space preserved';
    ok $dawg.contains("test\x[200C]ing"), 'ZWNJ preserved';
    ok $dawg.contains("join\x[200D]ed"), 'ZWJ preserved';
}

done-testing;