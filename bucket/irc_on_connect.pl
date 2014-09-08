sub irc_on_connect {
    Log("Connected...");

    return if &signal_plugin( "on_connect", {} );

    if ( &config("identify_before_autojoin") ) {
        Log("Identifying...");
        &say( nickserv => "identify $pass" );
    } else {
        Log("Skipping identify...");
        $stats{identified} = 1;
        $irc->yield( join => $channel );
    }
    Log("Done.");
}


