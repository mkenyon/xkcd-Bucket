sub irc_on_topic {
    my $chl   = $_[ARG1];
    my $topic = $_[ARG2];

    return if &signal_plugin( "on_topic", {chl => $chl, topic => $topic} );
}


