#!/usr/bin/env raku

use lib 'lib';
use DAWG;
use DAWG::Search::Fuzzy;

sub MAIN(
    Str $dictionary-file = '',                        # Dictionary file (optional)
    Bool :$interactive = False,                       # Interactive mode
    Int :$max-distance = 2,                          # Maximum edit distance
    Int :$suggestions = 5,                           # Number of suggestions
) {
    say "DAWG Spell Checker";
    say "=" x 50;
    
    # Load dictionary
    my $dawg = load-dictionary($dictionary-file);
    
    # Create fuzzy search instance
    my $spell-checker = DAWG::Search::Fuzzy.new(:$dawg);
    
    if $interactive {
        interactive-mode($spell-checker, :$max-distance, :$suggestions);
    } else {
        demo-mode($spell-checker, :$max-distance, :$suggestions);
    }
}

sub load-dictionary(Str $file) {
    my $dawg = DAWG.new;
    
    if $file.ends-with('.json') && $file.IO.e {
        # Load from JSON file
        say "Loading dictionary from $file...";
        use JSON::Fast;
        my $data = from-json($file.IO.slurp);
        
        if $data<words>:exists {
            for $data<words>.list -> $word {
                $dawg.add($word);
            }
            say "Loaded {+$data<words>} words";
        }
    } else {
        # Use built-in English dictionary
        say "Using built-in English dictionary...";
        my @common-words = <
            the be to of and a in that have I
            it for not on with he as you do at
            this but his by from they we say her she
            or an will my one all would there their what
            so up out if about who get which go me
            when make can like time no just him know take
            people into year your good some could them see
            other than then now look only come its over
            think also back after use two how our work
            first well way even new want because any these
            give day most us
            
            hello world computer programming algorithm database
            software hardware network security python javascript
            function variable constant parameter argument return
            method class object instance inheritance polymorphism
            array list dictionary hash table tree graph
            stack queue heap sort search insert delete
            update select where from join group order
            create read update delete REST API JSON
            HTML CSS JavaScript TypeScript React Angular
            Vue Node Express MongoDB PostgreSQL MySQL
            Docker Kubernetes Git GitHub GitLab Jenkins
            Linux Windows macOS Android iOS Swift
            Kotlin Java C++ Python Ruby PHP
            machine learning artificial intelligence neural network
            deep learning data science analytics visualization
            algorithm complexity performance optimization debug
            test unit integration deployment continuous
            agile scrum kanban sprint backlog story
            requirement specification documentation architecture
            design pattern singleton factory observer strategy
            command decorator adapter facade proxy bridge
        >;
        
        for @common-words -> $word {
            $dawg.add($word);
        }
        say "Loaded {+@common-words} words";
    }
    
    say "Minimizing DAWG...";
    $dawg.minimize;
    say "Dictionary ready!\n";
    
    return $dawg;
}

sub demo-mode($spell-checker, :$max-distance, :$suggestions) {
    say "Demo Mode - Testing common misspellings:\n";
    
    # Test words with common types of errors
    my @test-cases = (
        # Correct words
        'hello' => 'Correct spelling',
        'world' => 'Correct spelling',
        
        # Common misspellings
        'helo' => 'Missing letter',
        'wrold' => 'Transposed letters',
        'compter' => 'Missing letter',
        'progamming' => 'Missing letter',
        'algoritm' => 'Missing letter',
        'datbase' => 'Missing letter',
        
        # Substitutions
        'conputer' => 'Wrong letter',
        'pragramming' => 'Wrong letter',
        'algarithm' => 'Wrong letter',
        
        # Insertions
        'helllo' => 'Extra letter',
        'worlld' => 'Extra letter',
        'computter' => 'Extra letter',
        
        # Multiple errors
        'programing' => 'Missing letter',
        'algorthm' => 'Two errors',
        'datbse' => 'Two errors',
        
        # Not in dictionary
        'xyz' => 'Not a word',
        'qwerty' => 'Not a word',
    );
    
    for @test-cases -> $pair {
        my ($word, $description) = $pair.kv;
        check-spelling($spell-checker, $word, $description, :$max-distance, :$suggestions);
    }
    
    say "\n" ~ "=" x 50;
    say "Spell checking complete!";
}

sub interactive-mode($spell-checker, :$max-distance, :$suggestions) {
    say "Interactive Mode - Enter words to check (type 'quit' to exit):\n";
    
    loop {
        my $word = prompt("Enter word: ");
        
        last if !$word || $word eq 'quit';
        
        check-spelling($spell-checker, $word, '', :$max-distance, :$suggestions);
        say "";
    }
    
    say "\nGoodbye!";
}

sub check-spelling($spell-checker, Str $word, Str $description, :$max-distance, :$suggestions) {
    my $desc = $description ?? " ($description)" !! "";
    print "Checking '$word'$desc: ";
    
    # First check if the word exists
    if $spell-checker.dawg.contains($word) {
        say "✓ Correct";
        return;
    }
    
    # Get suggestions
    my @suggestions = $spell-checker.spell-check($word, :max-suggestions($suggestions));
    
    if @suggestions {
        say "✗ Misspelled";
        say "  Suggestions: " ~ @suggestions.map({ 
            my $w = $_<word> // '?';
            my $d = $_<distance> // '?';
            "$w (distance: $d)"
        }).join(', ');
    } else {
        # Try with larger distance
        my @distant = $spell-checker.search($word, :max-distance($max-distance));
        
        if @distant {
            say "✗ Misspelled";
            say "  Possible matches: " ~ @distant[0..min(4, @distant.end)].map({
                my $w = $_<word> // '?';
                my $d = $_<distance> // '?';
                "$w (distance: $d)"
            }).join(', ');
        } else {
            say "✗ No suggestions found";
        }
    }
}

sub prompt($message) {
    print $message;
    $*IN.get;
}