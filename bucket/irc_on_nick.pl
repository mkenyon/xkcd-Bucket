sub irc_on_nick {
    my ($who) = split /!/, $_[ARG0];
    my $newnick = $_[ARG1];

    return if &signal_plugin( "on_nick", {who => $who, newnick => $newnick} );

    return unless exists $stats{users}{genders}{lc $who};
    $stats{users}{genders}{lc $newnick} =
      delete $stats{users}{genders}{lc $who};
    &sql( "update genders set nick=? where nick=? limit 1",
        [ $newnick, $who ] );
    &load_gender($newnick);
}


