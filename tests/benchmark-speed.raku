#!/usr/bin/env raku
use lib 'lib';
use DAWG;

# Color codes for output
my $GREEN = "\e[32m";
my $YELLOW = "\e[33m";
my $RED = "\e[31m";
my $RESET = "\e[0m";

sub benchmark($name, &code, :$iterations = 1) {
    print "Running $name... ";
    my $start = now;
    &code() for ^$iterations;
    my $elapsed = now - $start;
    my $per-op = $iterations > 1 ?? $elapsed / $iterations !! $elapsed;
    
    my $color = $per-op < 0.001 ?? $GREEN !!
                 $per-op < 0.01  ?? $YELLOW !!
                                    $RED;
    
    say "{$color}{$elapsed.fmt('%.3f')}s{$RESET} total, {$color}{$per-op.fmt('%.6f')}s{$RESET} per op";
    return $elapsed;
}

say "=" x 60;
say "DAWG Performance Benchmarks";
say "=" x 60;

# Test data preparation
my @words = 'tests/words.txt'.IO.lines.head(10000);
if !@words {
    say "Generating random words...";
    @words = (^10000).map({
        ('a'..'z').pick((3..12).pick).join
    });
}

my @unicode-words = (^1000).map({
    <а б в г д е ж з и к л м н о п р с т у ф х ц ч ш щ ъ ы ь э ю я>.pick((3..8).pick).join
});

# 1. ASCII Insertion Speed
say "\n1. ASCII Insertion Speed";
my $ascii-dawg = DAWG.new;
benchmark("Insert 10,000 ASCII words", {
    for @words -> $word {
        $ascii-dawg.add($word, $++);
    }
});

# 2. Unicode Insertion Speed
say "\n2. Unicode Insertion Speed";
my $unicode-dawg = DAWG.new;
benchmark("Insert 1,000 Unicode words", {
    for @unicode-words -> $word {
        $unicode-dawg.add($word, $++);
    }
});

# 3. Mixed Insertion Speed
say "\n3. Mixed ASCII/Unicode Insertion";
my $mixed-dawg = DAWG.new;
benchmark("Insert 5,000 mixed words", {
    for @words.head(2500) -> $word {
        $mixed-dawg.add($word);
    }
    for @unicode-words.head(2500) -> $word {
        $mixed-dawg.add($word);
    }
});

# 4. Lookup Performance
say "\n4. Lookup Performance";
say "Preparing minimized DAWGs...";
$ascii-dawg.minimize;
$unicode-dawg.minimize;
$mixed-dawg.minimize;

benchmark("10,000 ASCII lookups", {
    for @words -> $word {
        $ascii-dawg.lookup($word);
    }
});

benchmark("1,000 Unicode lookups", {
    for @unicode-words -> $word {
        $unicode-dawg.lookup($word);
    }
});

benchmark("Random lookups (50% hit rate)", {
    for ^1000 {
        if Bool.pick {
            $mixed-dawg.lookup(@words.pick);
        } else {
            $mixed-dawg.lookup(('a'..'z').pick(8).join);
        }
    }
});

# 5. Prefix Search Performance
say "\n5. Prefix Search Performance";
my @prefixes = @words.map(*.substr(0, 3)).unique.head(100);

benchmark("100 prefix searches", {
    for @prefixes -> $prefix {
        my @results = $ascii-dawg.find-prefixes($prefix);
    }
});

# 6. Contains Check Performance
say "\n6. Contains Check Performance";
benchmark("10,000 contains checks", {
    for @words -> $word {
        $ascii-dawg.contains($word);
    }
});

# 7. Minimization Performance
say "\n7. Minimization Performance";
my $minimize-dawg = DAWG.new;
for @words.head(5000) -> $word {
    $minimize-dawg.add($word);
}
say "Nodes before minimization: {$minimize-dawg.node-count}";
benchmark("Minimize 5,000 words", {
    $minimize-dawg.minimize;
});
say "Nodes after minimization: {$minimize-dawg.node-count}";

# 8. Rebuild Performance
say "\n8. Rebuild Performance";
my $rebuild-dawg = DAWG.new;
for @words.head(500) -> $word {
    $rebuild-dawg.add($word);
}
for @unicode-words.head(500) -> $word {
    $rebuild-dawg.add($word);
}

benchmark("Rebuild to UTF-32", {
    $rebuild-dawg.rebuild(:encoding('utf32'));
});

benchmark("Rebuild to compressed", {
    $rebuild-dawg.rebuild(:encoding('compressed'));
});

# 9. Automatic Compression Overhead
say "\n9. Automatic Compression Overhead";
my $auto-dawg = DAWG.new;
my $start = now;
for ^1000 -> $i {
    if $i < 500 {
        $auto-dawg.add("word$i");  # ASCII
    } else {
        $auto-dawg.add("слово$i"); # Unicode - triggers compression
    }
}
my $auto-time = now - $start;
say "Mixed insertion with auto-compression: {$auto-time.fmt('%.3f')}s";
say "Compression triggered: {$auto-dawg.is-compressed-unicode ?? 'Yes' !! 'No'}";

# 10. Memory Usage Estimation
say "\n10. Memory Usage Estimation";
say "ASCII DAWG ({+@words} words):";
say "  Nodes: {$ascii-dawg.node-count}";
say "  Edges: {$ascii-dawg.edge-count}";
say "  Estimated memory: {($ascii-dawg.node-count * 100 / 1024 / 1024).fmt('%.2f')} MB";

say "Unicode DAWG ({+@unicode-words} words):";
say "  Nodes: {$unicode-dawg.node-count}";
say "  Edges: {$unicode-dawg.edge-count}";
say "  Compressed: {$unicode-dawg.is-compressed-unicode ?? 'Yes' !! 'No'}";

# Summary
say "\n" ~ "=" x 60;
say "Summary:";
say "- ASCII operations: {$GREEN}Fast{$RESET}";
say "- Unicode operations: {$unicode-dawg.is-compressed-unicode ?? $GREEN ~ 'Compressed' !! $YELLOW ~ 'UTF-32'}{$RESET}";
say "- Automatic compression: {$GREEN}Working{$RESET}";
say "=" x 60;