sub irc_on_chan_sync {
    my $chl = $_[ARG0];
    Log "Sync done for $chl";

    return if &signal_plugin( "on_chan_sync", {chl => $chl} );

    if ( not &DEBUG and $chl eq $channel ) {
        Log("Autojoining channels");
        foreach my $chl ( &config("logchannel"), keys %{$config->{autojoin}} ) {
            $irc->yield( join => $chl );
            Log("... $chl");
        }
    }
}


