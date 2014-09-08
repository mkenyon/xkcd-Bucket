sub cached_reply {
    my ( $chl, $who, $extra, $type ) = @_;
    my $line = $fcache{$type}[ rand( @{$fcache{$type}} ) ];
    Log "cached '$type' reply: $line->{verb} $line->{tidbit}";

    my $tidbit = $line->{tidbit};

    if ( $type eq 'band name reply' ) {
        if ( $tidbit =~ /\$band/i ) {
            $tidbit =~ s/\$band/$extra/ig;
        }

        $extra = "";
    } elsif ( $type eq 'tumblr name reply' ) {
        $extra =~ s/[^a-z0-9]+//ig;
        $extra = lc $extra;
        if ( $tidbit =~ /\$band/i ) {
            $tidbit =~ s/\$band/$extra/ig;
        }

        $extra = "";
    } elsif ( $type eq 'pickup full'
        or $type eq 'drops item' )
    {
        $extra = [$extra] unless ref $extra eq 'ARRAY';
        my $newitem;
        my @olditems = @$extra;
        $newitem = shift @olditems if $type eq 'pickup full';

        my $olditems = &make_list(@olditems);
        if ( $tidbit =~ /\$item/i ) {
            $tidbit =~ s/\$item/$newitem/ig;
        }
        if ( $tidbit =~ /\$giveitem/i ) {
            $tidbit =~ s/\$giveitem/$olditems/ig;
        }
    } elsif ( $type eq 'takes item'
        or $type eq 'duplicate item'
        or $type eq 'list items' )
    {
        if ( $tidbit =~ /\$item/i ) {
            $tidbit =~ s/\$item/$extra/ig;
        }

        if ( $tidbit =~ /\$inventory/i ) {
            $tidbit =~ s/\$inventory/&inventory/eg;
        }

        $extra = "";
    }

    $tidbit = &expand( $who, $chl, $tidbit, 0, undef );
    return unless $tidbit;

    if ( $line->{verb} eq '<action>' ) {
        &do( $chl => $tidbit );
    } elsif ( $line->{verb} eq '<reply>' ) {
        &say( $chl => $tidbit );
    } else {
        $extra ||= "";
        &say( $chl => "$extra$tidbit" );
    }
}


