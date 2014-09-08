sub check_band_name {
    my $bag = shift;

    my $handles = &get_band_name_handles();
    return unless $handles;

    return unless ref $bag->{words} eq 'ARRAY' and @{$bag->{words}} == 3;
    $bag->{start} = time;
    my @trimmed_words = map { s/[^0-9a-zA-Z'\-]//g; lc $_ } @{$bag->{words}};
    if (   $trimmed_words[0] eq $trimmed_words[1]
        or $trimmed_words[0] eq $trimmed_words[2]
        or $trimmed_words[1] eq $trimmed_words[2] )
    {
        return;
    }

    Log "Executing band name word count (@trimmed_words)";
    $handles->{lookup}->execute(@trimmed_words);
    my @words;
    my $delayed;
    my $found = 0;
    while ( my $line = $handles->{lookup}->fetchrow_hashref ) {
        my $entry = {
            word  => $line->{word},
            id    => $line->{id},
            count => $line->{lines},
            start => time
        };

        if ( @words < 2 ) {
            Log "processing $entry->{word} ($entry->{count})\n";
            $entry->{sth} = $handles->{dbh}->prepare(
                "select line
                 from word2line
                 where word = ?
                 order by line"
            );
            $entry->{sth}->execute( $entry->{id} );
            $entry->{cur} = $entry->{sth}->fetchrow_hashref;
            unless ( $entry->{cur} ) {
                Log "Not all words found, new band declared";
                $bag->{elapsed} = time - $bag->{start};
                &add_new_band($bag);
                return;
            }
            $entry->{next_id} = $entry->{cur}{line};
            $entry->{elapsed} = time - $entry->{start};
            push @words, $entry;
        } else {
            Log "delaying processing $entry->{word} ($entry->{count})\n";
            $delayed = $entry;
        }
    }

    @words = sort { $a->{next_id} <=> $b->{next_id} } @words;

    my @union;
    Log "Finding union";
    while (1) {
        unless ( $words[0]->{next_id} and $words[1]->{next_id} ) {
            &add_new_band($bag);
            return;
        }

        if ( $words[0]->{next_id} == $words[1]->{next_id} ) {
            push @union, $words[0]->{next_id};
        }

        unless ( $words[0]->{next_id} < $words[1]->{next_id} ) {
            ( $words[1], $words[0] ) = ( $words[0], $words[1] );
        }

        unless ($words[0]->{sth}
            and $words[0]->{cur} = $words[0]->{sth}->fetchrow_hashref )
        {
            last;
        }
        $words[0]->{next_id} = $words[0]->{cur}{line};
    }

    if ( @union > 0 ) {
        Log "Union ids: " . @union;
        my $sth =
          $handles->{dbh}->prepare(
                "select line from word2line where word = ?  and line in (?"
              . ( ",?" x ( @union - 1 ) )
              . ") limit 1" );

        my $res = $sth->execute( $delayed->{id}, @union );
        $found = $res > 0;
    } else {
        $found = 1;
    }

    Log "Found = $found";
    unless ($found) {
        $bag->{elapsed} = time - $bag->{start};
        &add_new_band($bag);
        return;
    }
}


