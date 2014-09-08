sub load_plugin {
    my $name = shift;

    unless ( &config("plugin_dir") ) {
        Log("Plugin directory not defined, can't load plugins.");
        return 0;
    }

    # make sure there's no funny business in the plugin name (like .., etc)
    $name =~ s/\W+//g;

    Log("Loading plugin: $name");
    if ( exists $stats{loaded_plugins}{$name} ) {
        &unload_plugin($name);
    }

    unless ( open PLUGIN, "<", &config("plugin_dir") . "/plugin.$name.pl" ) {
        Log(
            "Can't find plugin.$name.pl in " . &config("plugin_dir") . ": $!" );
        return 0;
    }

    # enable slurp mode
    local $/;
    my $code = <PLUGIN>;
    close PLUGIN;

    unless ( $code =~ /^# BUCKET PLUGIN/ ) {
        Log("Invalid plugin format.");
        return 0;
    }

    my $package = "Bucket::Plugin::$name";
    eval join ";", "{",
      "package $package",
      'use lib "' . &config("plugin_dir") . '"',
      $code,
      "}";
    if ($@) {
        Log("Error loading plugin: $@");
        return 0;
    }

    my @signals;
    eval { @signals = "$package"->signals(); };
    if ($@) {
        Log("Error loading plugin signals: $@");
    } elsif (@signals) {
        Log("Registering signals: @signals");
        foreach my $signal (@signals) {
            &register( $name, $signal );
        }
    }

    my @commands;
    eval { @commands = "$package"->commands(); };
    if ($@) {
        Log("Error loading plugin commands: $@");
    } elsif (@commands) {
        Log( "Registering commands: ",
            &make_list( map { $_->{label} } @commands ) );
        foreach my $command (@commands) {
            $command->{plugin} = $name;
            push @registered_commands, $command;
        }
    }

    my %plugin_settings;
    eval { %plugin_settings = "$package"->settings(); };
    if ($@) {
        Log("Error loading plugin settings: $@");
    } elsif (%plugin_settings) {
        Log( "Defined settings: ", &make_list( sort keys %plugin_settings ) );
        while ( my ( $key, $value ) = each %plugin_settings ) {
            $config_keys{$key} = $value;
        }
    }

    &signal_plugin( "onload", {name => $name} );

    $stats{loaded_plugins}{$name} = "@signals";

    return 1;
}


