sub unregister {
    my ( $name, $signal ) = @_;

    Log("Unregistering plugin $name from $signal signals");
    unless ( exists $plugin_signals{$signal} ) {
        $plugin_signals{$signal} = [];
    }

    my @signals = ($signal);
    if ( $signal eq "*" ) {
        @signals = keys %plugin_signals;
    }

    foreach my $sig (@signals) {
        if ( grep { $_ eq $name } @{$plugin_signals{$sig}} ) {
            $plugin_signals{$sig} =
              [ grep { $_ ne $name } @{$plugin_signals{$sig}} ];
        }
    }
}


