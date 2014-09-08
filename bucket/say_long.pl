sub say_long {
    my $chl  = shift;
    my $text = "@_";

    while ( length($text) > 300 and $text =~ s/(.{0,300})\s+(.*)/$2/ ) {
        &say( $chl, $1 );
    }
    &say( $chl, $text ) if $text =~ /\S/;
}


