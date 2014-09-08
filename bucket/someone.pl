sub someone {
    my $channel = shift;
    my @exclude = @_;
    my %nicks   = map { lc $_ => $_ } keys %{$stats{users}{$channel}};

    # we're never someone
    delete $nicks{$nick};

    # ignore people who asked to be excluded
    if ( ref $config->{exclude} ) {
        delete @nicks{map { lc } keys %{$config->{exclude}}};
    }

    # if we were supplied additional nicks to ignore, remove them
    foreach my $exclude (@exclude) {
        delete $nicks{$exclude};
    }

    return 'someone' unless keys %nicks;
    return ( values %nicks )[ rand( keys %nicks ) ];
}


