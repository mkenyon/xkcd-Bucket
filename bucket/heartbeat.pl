sub heartbeat {
    $_[KERNEL]->delay( heartbeat => 60 );

    return if &signal_plugin( "heartbeat", {} );

    if ( my $file_input = &config("file_input") ) {
        rename $file_input, "$file_input.processing";
        if ( open FI, "$file_input.processing" ) {
            while (<FI>) {
                chomp;
                my ( $output, $who, $msg ) = split ' ', $_, 3;
                $msg =~ s/\s\s+/ /g;
                $msg =~ s/^\s+|\s+$//g;
                $msg = &trim($msg);

                Log "file input: $output, $who: $msg";

                if ( $msg eq 'something random' ) {
                    &lookup(
                        editable  => 0,
                        addressed => 1,
                        chl       => $output,
                        who       => &someone($channel),
                    );
                } else {
                    &lookup(
                        editable  => 0,
                        addressed => 1,
                        chl       => $output,
                        who       => $who,
                        msg       => $msg,
                    );
                }
            }

            close FI;
        }
        unlink "$file_input.processing";
    }

    my $chl = &DEBUG ? $channel : $mainchannel;
    $last_activity{$chl} ||= time;

    return
      if &config("random_wait") == 0
      or time - $last_activity{$chl} < 60 * &config("random_wait");

    return if $stats{last_idle_time}{$chl} > $last_activity{$chl};

    $stats{last_idle_time}{$chl} = time;

    my %sources = (
        MLIA => [
            "http://feeds.feedburner.com/mlia", qr/MLIA.*/,
            "feedburner:origLink"
        ],
        SMDS => [
            "http://twitter.com/statuses/user_timeline/62581962.rss",
            qr/^shitmydadsays: "|"$/, "link"
        ],
        FAPSB => [
            "http://twitter.com/statuses/user_timeline/83883736.rss",
            qr/^FakeAPStylebook: /, "link"
        ],
        FAF => [
            "http://twitter.com/statuses/user_timeline/14062390.rss",
            qr/^fakeanimalfacts: |http:.*/, "link"
        ],
        Batman => [
            "http://twitter.com/statuses/user_timeline/126881128.rss",
            qr/^God_Damn_Batman: |http:.*/, "link"
        ],
        factoid => 1
    );
    my $source = &config("idle_source");

    if ( $source eq 'random' ) {
        $source = ( keys %sources )[ rand keys %sources ];
    }

    $stats{chatter_source}{$source}++;

    if ( $source ne 'factoid' ) {
        Log "Looking up $source story";
        my ( $story, $url ) = &read_rss( @{$sources{$source}} );
        if ($story) {
            &say( $chl => $story );
            $stats{last_fact}{$chl} = $url;
            return;
        }
    }

    &lookup(
        chl          => $chl,
        who          => $nick,
        idle         => 1,
        exclude_verb => [ split( ',', &config("random_exclude_verbs") ) ],
    );
}


