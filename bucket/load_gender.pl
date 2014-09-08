sub load_gender {
    my $who = shift;

    Log "Looking up ${who}'s gender...";
    &sql( 'select gender from genders where nick = ? limit 1',
        [$who], {cmd => 'load_gender', nick => $who, db_type => 'SINGLE'} );
}


