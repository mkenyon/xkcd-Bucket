sub signal_plugin {
    my ( $sig_name, $data ) = @_;
    my $rc = 0;

   # call each registered plugin, in the order they were registered. First the
   # plugins that ask for specific signals, then the ones that want all signals.

    # The return value from the plugin can control future processing. A true
    # value (positive or negative) means no further processing will be done in
    # the core. If the return value is negative, no further plugins will be
    # called.

    if ( exists $plugin_signals{$sig_name} ) {
        foreach my $plugin ( @{$plugin_signals{$sig_name}} ) {
            eval {
                $data->{rc}{plugin} =
                  "Bucket::Plugin::$plugin"->route( $sig_name, $data );
            };
            $rc ||= $data->{rc}{plugin};

            if ($@) {
                Log("Error when signalling $sig_name to $plugin: $@");
            }

            last if $rc < 0;
        }
    }

    return $rc if $rc < 0;

    if ( exists $plugin_signals{"*"} ) {
        foreach my $plugin ( @{$plugin_signals{"*"}} ) {
            eval {
                $data->{rc}{plugin} =
                  "Bucket::Plugin::$plugin"->route( $sig_name, $data );
            };
            $rc ||= $data->{rc}{plugin};

            if ($@) {
                Log("Error when signalling $sig_name to $plugin: $@");
            }

            last if $rc < 0;
        }
    }

    return $rc;
}


