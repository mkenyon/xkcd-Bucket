sub do {
    my $chl    = shift;
    my $action = "@_";

    my %data = ( chl => $chl, text => $action );
    return if &signal_plugin( "do", \%data );
    ( $chl, $action ) = ( $data{chl}, $data{text} );

    if ( $chl =~ m#^/# ) {
        if ( open FO, ">>", $chl ) {
            print FO "D $action\n";
            close FO;
        } else {
            Log "Failed to write to $chl: $!";
        }
        return;
    }

    $irc->yield( ctcp => $chl => "ACTION $action" );
}


