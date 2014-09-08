sub unload_plugin {
    my $name = shift;

    Log("Unloading plugin: $name");
    &unregister( $name, "*" );

    @registered_commands = grep { $_->{plugin} ne $name } @registered_commands;

    delete $stats{loaded_plugins}{$name};
}


