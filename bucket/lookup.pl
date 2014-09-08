sub lookup {
    my %params = @_;
    my $sql;
    my $type;
    my @placeholders;

    return if &signal_plugin( "lookup", \%params );

    if ( exists $params{msg} ) {
        $sql          = "fact = ?";
        $type         = "single";
        $params{msg}  = &decommify( $params{msg} );
        @placeholders = ( $params{msg} );
    } elsif ( exists $params{msgs} ) {
        $sql = "fact in (" . join( ", ", map { "?" } @{$params{msgs}} ) . ")";
        @placeholders = map { &decommify($_) } @{$params{msgs}};
        $type = "multiple";
    } else {
        $sql  = "1";
        $type = "none";
    }

    if ( exists $params{verb} ) {
        $sql .= " and verb = ?";
        push @placeholders, $params{verb};
    } elsif ( exists $params{exclude_verb} ) {
        $sql .= " and verb not in ("
          . join( ", ", map { "?" } @{$params{exclude_verb}} ) . ")";
        push @placeholders, @{$params{exclude_verb}};
    }

    if ( $params{starts} ) {
        $sql .= " and tidbit like ?";
        push @placeholders, "$params{starts}\%";
    } elsif ( $params{search} ) {
        $sql .= " and tidbit like ?";
        push @placeholders, "\%$params{search}\%";
    }

    &sql(
        "select id, fact, verb, tidbit from bucket_facts
          where $sql order by rand(" . int( rand(1e6) ) . ') limit 1',
        \@placeholders,
        {
            %params,
            cmd       => "fact",
            orig      => $params{orig} || $params{msg},
            addressed => $params{addressed} || 0,
            editable  => $params{editable} || 0,
            op        => $params{op} || 0,
            type      => $params{type} || "irc_public",
            db_type   => 'SINGLE',
        }
    );
}


