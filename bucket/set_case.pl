sub set_case {
    my ( $var, $value ) = @_;

    my $case;
    $var =~ s/\W+//g;
    if ( $var =~ /^[A-Z_]+$/ ) {
        $case = "U";
    } elsif ( $var =~ /^[A-Z][a-z_]+$/ ) {
        $case = "u";
    } else {
        $case = "l";
    }

    # values that already include capitals are never modified
    if ( $value =~ /[A-Z]/ or $case eq "l" ) {
        return $value;
    } elsif ( $case eq 'U' ) {
        return uc $value;
    } elsif ( $case eq 'u' ) {
        return join " ", map { ucfirst } split ' ', $value;
    }
}


