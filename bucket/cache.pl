sub cache {
    my ( $kernel, $key ) = @_;
    &sql( 'select verb, tidbit from bucket_facts where fact = ?',
        [$key], {cmd => "cache", key => $key, db_type => 'MULTIPLE'} );
}


