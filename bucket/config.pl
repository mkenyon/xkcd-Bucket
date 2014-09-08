sub config {
    my ( $key, $val ) = @_;

    if ( defined $val ) {
        return $config->{$key} = $val;
    }

    if ( defined $config->{$key} ) {
        return $config->{$key};
    } elsif ( exists $config_keys{$key} ) {
        return $config_keys{$key}[1];
    } else {
        return undef;
    }
}


