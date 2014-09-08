sub Report {
    my $delay = shift if $_[0] =~ /^\d+$/;
    my $logchannel = &DEBUG ? $channel : &config("logchannel");
    unshift @_, "REPORT:" if &DEBUG;

    if ( $logchannel and $irc ) {
        if ($delay) {
            Log "Delayed msg ($delay): @_";
            POE::Kernel->delay_add(
                delayed_post => 2 * $delay => $logchannel => "@_" );
        } else {
            &say( $logchannel, "@_" );
        }
    }
}


