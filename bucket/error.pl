sub error {
    my ( $chl, $who, $prefix ) = @_;
    &cached_reply( $chl, $who, $prefix, "don't know" );
}


