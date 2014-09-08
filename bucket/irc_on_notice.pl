sub irc_on_notice {
    my ($who) = split /!/, $_[ARG0];
    my $msg = $_[ARG2];

    Log("Notice from $who: $msg");

    return if &signal_plugin( "on_notice", {who => $who, msg => $msg} );

    return if $stats{identified};
    if (
        lc $who eq lc &config("nickserv_nick")
        and $msg =~ (
              &config("nickserv_msg")
            ? &config("nickserv_msg")
            : qr/Password accepted|(?:isn't|not) registered|You are now identified/
        )
      )
    {
        Log("Identified, joining $channel");
        $irc->yield( mode => $nick => &config("user_mode") );
        unless ( &config("hide_hostmask") ) {
            $irc->yield( mode => $nick => "-x" );
        }

        $irc->yield( join => $channel );
        $stats{identified} = 1;
    }
}


