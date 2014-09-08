sub register {
    my ( $name, $signal ) = @_;

    Log("Registering plugin $name for $signal signals");
    unless ( exists $plugin_signals{$signal} ) {
        $plugin_signals{$signal} = [];
    }

    if ( grep { $_ eq $name } @{$plugin_signals{$signal}} ) {
        Log("Already registered!");
    } else {
        push @{$plugin_signals{$signal}}, $name;
    }
}


