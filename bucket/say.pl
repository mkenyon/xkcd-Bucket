sub say {
    my $chl  = shift;
    my $text = "@_";

    my %data = ( chl => $chl, text => $text );
    return if &signal_plugin( "say", \%data );
    ( $chl, $text ) = ( $data{chl}, $data{text} );

    if ( $chl =~ m#^/# ) {
        Log "Writing to '$chl'";
        if ( open FO, ">>", $chl ) {
            print FO "S $text\n";
            close FO;
        } else {
            Log "Failed to write to $chl: $!";
        }
        return;
    }

    $irc->yield( privmsg => $chl => $text );
}


