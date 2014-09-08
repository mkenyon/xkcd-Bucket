sub random_item_cache {
    my $kernel = shift;
    my $force  = shift;
    my $limit  = &config("random_item_cache_size");
    $limit =~ s/\D//g;

    if ( not $force and @random_items >= $limit ) {
        return;
    }

    &sql( "select what, user from bucket_items order by rand() limit $limit",
        undef, {cmd => "itemcache", db_type => 'MULTIPLE'} );
}


