# DAWG Module Use Cases

The DAWG (Directed Acyclic Word Graph) module provides efficient string storage and retrieval with sub-microsecond lookup times and significant memory savings. Here are practical use cases where DAWG excels.

## 1. Spell Checkers and Autocorrect Systems

DAWG is ideal for spell checking applications due to its fast lookup and fuzzy search capabilities.

```raku
use DAWG;
use DAWG::Search::Fuzzy;

# Load dictionary
my $dict = DAWG.new;
$dict.load('english-dictionary.dawg');

# Check spelling
sub check-spelling($word) {
    return True if $dict.contains($word);
    
    # Find suggestions using fuzzy search
    my $fuzzy = DAWG::Search::Fuzzy.new($dict);
    my @suggestions = $fuzzy.search($word, :max-distance(2), :limit(5));
    
    return @suggestions;
}

# Usage
my $result = check-spelling("recieve");  # Returns suggestions: ["receive"]
```

## 2. Autocomplete and Type-Ahead Features

Perfect for search boxes, code editors, and command-line interfaces.

```raku
use DAWG;

my $dawg = DAWG.new;

# Load command history or search terms
$dawg.add($_) for <
    git-commit git-checkout git-branch git-merge
    git-rebase git-reset git-stash git-pull git-push
>;

# Autocomplete function
sub autocomplete($prefix, :$limit = 10) {
    $dawg.prefixed($prefix, :$limit);
}

# Usage in CLI
my @suggestions = autocomplete("git-c");  # ["git-commit", "git-checkout"]
```

## 3. Domain Name and URL Validation

Efficiently validate and suggest domain names or URL paths.

```raku
use DAWG;

my $domains = DAWG.new;

# Load valid TLDs and common domains
$domains.add($_) for <
    .com .org .net .edu .gov .io .dev .app
    google.com facebook.com github.com
>;

# Validate and suggest domains
sub validate-domain($input) {
    my ($name, $tld) = $input.split('.');
    
    # Check if TLD exists
    return False unless $domains.contains(".$tld");
    
    # Suggest similar domains if not exact match
    if !$domains.contains($input) {
        my @similar = $domains.prefixed($name).grep(*.ends-with(".$tld"));
        return @similar;
    }
    
    return True;
}
```

## 4. Code Analysis and Symbol Tables

Analyze codebases for variable names, function definitions, and imports.

```raku
use DAWG;
use DAWG::Search::Pattern;

my $symbols = DAWG.new;

# Index all symbols from a codebase
sub index-codebase($dir) {
    for dir($dir, :r).grep(*.extension eq 'raku') -> $file {
        my $content = $file.slurp;
        
        # Extract function names
        for $content.match(/:g 'sub' \s+ (\w+)/, :g) -> $match {
            $symbols.add-with-value($match[0].Str, $file.Str);
        }
        
        # Extract class names
        for $content.match(/:g 'class' \s+ (\w+)/, :g) -> $match {
            $symbols.add-with-value($match[0].Str, $file.Str);
        }
    }
}

# Find all symbols matching a pattern
my $pattern-search = DAWG::Search::Pattern.new($symbols);
my @test-functions = $pattern-search.search("test_*");
```

## 5. Geographic Data and Address Validation

Store and validate postal codes, city names, and addresses efficiently.

```raku
use DAWG;

my $geo = DAWG.new;

# Load postal codes with city mappings
$geo.add-with-value("10001", "New York, NY");
$geo.add-with-value("90210", "Beverly Hills, CA");
$geo.add-with-value("60601", "Chicago, IL");

# Validate and lookup
sub lookup-postal-code($code) {
    $geo.get-value($code) // "Unknown postal code";
}

# Find postal codes by prefix (useful for forms)
sub suggest-postal-codes($prefix) {
    $geo.prefixed($prefix, :limit(10));
}
```

## 6. Natural Language Processing

Build efficient dictionaries for NLP tasks with frequency data.

```raku
use DAWG;

my $corpus = DAWG.new;

# Build frequency dictionary from text
sub build-frequency-dict(@texts) {
    for @texts -> $text {
        for $text.words.map(*.lc) -> $word {
            my $count = $corpus.get-value($word) // 0;
            $corpus.add-with-value($word, $count + 1);
        }
    }
}

# Get word frequency
sub word-frequency($word) {
    $corpus.get-value($word.lc) // 0;
}

# Find rare words (frequency < threshold)
sub find-rare-words($threshold = 5) {
    $corpus.words.grep({ $corpus.get-value($_) < $threshold });
}
```

## 7. Configuration and Feature Flags

Manage application configuration keys and feature flags.

```raku
use DAWG;

my $config = DAWG.new;

# Load configuration keys
$config.add-with-value("app.name", "MyApp");
$config.add-with-value("app.version", "1.2.3");
$config.add-with-value("feature.dark-mode", "enabled");
$config.add-with-value("feature.beta-ui", "disabled");

# Get all feature flags
sub get-feature-flags() {
    $config.prefixed("feature.").map({
        $_ => $config.get-value($_)
    }).Hash;
}

# Check if feature is enabled
sub feature-enabled($feature) {
    $config.get-value("feature.$feature") eq 'enabled';
}
```

## 8. Log Analysis and Pattern Detection

Efficiently search through log entries and detect patterns.

```raku
use DAWG;
use DAWG::Search::Pattern;

my $logs = DAWG.new;

# Index log entries by timestamp
sub index-logs($log-file) {
    for $log-file.IO.lines -> $line {
        if $line ~~ /^(\d+ '-' \d+ '-' \d+ \s+ \d+ ':' \d+ ':' \d+) \s+ (.+)$/ {
            my ($timestamp, $message) = $0.Str, $1.Str;
            $logs.add-with-value($timestamp, $message);
        }
    }
}

# Find all error logs
my $pattern = DAWG::Search::Pattern.new($logs);
my @errors = $pattern.search("*ERROR*");
```

## 9. Game Development - Valid Word Lists

Perfect for word games like Scrabble, Wordle, or crossword puzzles.

```raku
use DAWG;

my $game-dict = DAWG.new;

# Load valid game words
$game-dict.add($_) for <APPLE ORANGE BANANA GRAPE>;

# Validate word placement
sub is-valid-word($word) {
    $game-dict.contains($word.uc);
}

# Find all words that can be made with given letters
sub find-possible-words(@letters, $length) {
    my $pattern = @letters.map('*').join;
    $game-dict.words
        .grep(*.chars == $length)
        .grep({ 
            my @word-letters = .comb;
            @word-letters.all ∈ @letters
        });
}
```

## 10. API Endpoint Management

Manage and validate API routes efficiently.

```raku
use DAWG;

my $routes = DAWG.new;

# Register API endpoints with handlers
$routes.add-with-value("/api/users", "UserController.list");
$routes.add-with-value("/api/users/:id", "UserController.show");
$routes.add-with-value("/api/posts", "PostController.list");
$routes.add-with-value("/api/posts/:id", "PostController.show");

# Find matching route
sub match-route($path) {
    # Direct match
    return $routes.get-value($path) if $routes.contains($path);
    
    # Pattern match for dynamic routes
    my @parts = $path.split('/');
    for $routes.words.grep(*.contains(':')) -> $pattern {
        my @pattern-parts = $pattern.split('/');
        if @parts.elems == @pattern-parts.elems {
            my $matches = True;
            for @pattern-parts.kv -> $i, $part {
                next if $part.starts-with(':');
                $matches = False unless @parts[$i] eq $part;
            }
            return $routes.get-value($pattern) if $matches;
        }
    }
    
    return Nil;
}
```

## Performance Benefits

All these use cases benefit from DAWG's key features:

- **Sub-microsecond lookups** - Critical for real-time applications
- **Memory efficiency** - 75% space savings with ASCII encoding
- **Persistence** - Save/load state between sessions
- **Memory mapping** - Instant startup with large datasets
- **Pattern matching** - Flexible searches with wildcards
- **Fuzzy search** - Typo-tolerant matching

## When to Use DAWG

DAWG is ideal when you need:
- Fast string lookups (spell checkers, validators)
- Prefix searches (autocomplete, type-ahead)
- Memory-efficient storage (large dictionaries, logs)
- Pattern matching (code analysis, log parsing)
- Fuzzy matching (spell correction, similar words)
- Persistent string storage (configuration, caches)

## When NOT to Use DAWG

Consider alternatives when you need:
- Frequent updates (DAWG is optimized for read-heavy workloads)
- Complex data structures (DAWG stores strings with optional integer values)
- Full-text search (use dedicated search engines)
- Sorted iteration in custom orders (DAWG maintains its own order)