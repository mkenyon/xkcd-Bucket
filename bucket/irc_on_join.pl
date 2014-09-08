sub irc_on_join {
    my ($who) = split /!/, $_[ARG0];

    return if &signal_plugin( "on_join", {who => $who} );

    return if exists $stats{users}{genders}{lc $who};

    &load_gender($who);
}


