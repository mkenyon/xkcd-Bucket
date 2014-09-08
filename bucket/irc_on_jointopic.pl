sub irc_on_jointopic {
    my ( $chl, $topic ) = @{$_[ARG2]}[ 0, 1 ];
    $topic =~ s/ ARRAY\(0x\w+\)$//;

    return if &signal_plugin( "jointopic", {chl => $chl, topic => $topic} );
}


