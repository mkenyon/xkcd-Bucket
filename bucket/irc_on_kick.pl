sub irc_on_kick {
    my ($kicker) = split /!/, $_[ARG0];
    my $chl      = $_[ARG1];
    my $kickee   = $_[ARG2];
    my $desc     = $_[ARG3];

    Log "$kicker kicked $kickee from $chl";

    return
      if &signal_plugin(
        "on_kick",
        {
            kicker => $kicker,
            chl    => $chl,
            kickee => $kickee,
            desc   => $desc
        }
      );

    &lookup(
        msgs => [ "$kicker kicked $kickee", "$kicker kicked someone" ],
        chl  => $chl,
        who  => $kickee,
        op   => 1,
        type => 'irc_kick',
    );
}


