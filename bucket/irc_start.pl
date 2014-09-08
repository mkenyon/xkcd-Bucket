sub irc_start {
    Log "DB Connect...";
    $_[KERNEL]->post(
        db       => 'CONNECT',
        DSN      => &config("db_dsn"),
        USERNAME => &config("db_username"),
        PASSWORD => &config("db_password"),
        EVENT    => 'db_success',
    );

    $irc->yield( register => 'all' );
    $_[HEAP]->{connector} = POE::Component::IRC::Plugin::Connector->new();
    $irc->plugin_add( Connector => $_[HEAP]->{connector} );

    # find out which variables should be preloaded
    &sql(
        'select name, count(value) num
          from bucket_vars vars
               left join bucket_values
               on vars.id = var_id
          group by name', undef,
        {cmd => "load_vars", db_type => 'MULTIPLE'}
    );

    foreach my $reply (
        "Don't know",
        "takes item",
        "drops item",
        "pickup full",
        "list items",
        "duplicate item",
        "band name reply",
        "tumblr name reply",
        "haiku detected",
        "uses reply"
      )
    {
        &cache( $_[KERNEL], $reply );
    }
    &random_item_cache( $_[KERNEL] );
    $stats{preloaded_items} = &config("inventory_preload");

    $irc->yield(
        connect => {
            Nick     => $nick,
            Username => &config("username") || "bucket",
            Ircname  => &config("irc_name") || "YABI",
            Server   => &config("server") || "irc.foonetic.net",
            Port     => &config("port") || "6667",
            Flood    => 0,
            UseSSL   => &config("ssl") || 0,
            useipv6  => &config("ipv6") || 0
        }
    );

    if ( &config("bucketlog") and -f &config("bucketlog") and open BLOG,
        &config("bucketlog") )
    {
        seek BLOG, 0, SEEK_END;
    }

    $_[KERNEL]->delay( heartbeat => 10 );

    return if &signal_plugin( "start", {} );
}


