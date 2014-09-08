sub irc_on_disconnect {
    Log("Disconnected...");

    return if &signal_plugin( "on_disconnect", {} );

    close LOG;
    $irc->call( unregister => 'all' );
    exit;
}


