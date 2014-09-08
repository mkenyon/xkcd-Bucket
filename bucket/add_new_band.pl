sub add_new_band {
    my $bag = shift;
    &sql(
        'insert into bucket_values (var_id, value)
         values ( (select id from bucket_vars where name = ? limit 1), ?);',
        [ &config("band_var"), $bag->{stripped_name} ],
        {%$bag, cmd => "new band name"}
    );

    $bag->{name} =~ s/(^| )(\w)/$1\u$2/g;
    Report "Learned a new band name from $bag->{who} in $bag->{chl} ("
      . join( " ", &round_time( $bag->{elapsed} ) )
      . "): $bag->{name}";
    if ( &config("tumblr_name") > rand(100) ) {
        &cached_reply( $bag->{chl}, $bag->{who}, $bag->{name},
            "tumblr name reply" );
    } else {
        &cached_reply( $bag->{chl}, $bag->{who}, $bag->{name},
            "band name reply" );
    }
}


