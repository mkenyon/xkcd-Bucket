sub get_var {
    my ( $record, $var, $conjugate ) = @_;

    $var = lc $var;

    return "\$$var" unless $record->{vals} or $record->{cache};
    my @values =
      exists $record->{vals}
      ? @{$record->{vals}}
      : ( shift @{$record->{cache}} );
    return "\$$var" unless @values;
    my $value = $values[ rand @values ];
    $value =~ s/\$//g;

    if ( ref $conjugate eq 'CODE' ) {
        Log "Conjugating $value ($conjugate)";
        Log join ", ", "past=" . \&past, "s_form=" . \&s_form,
          "gerund=" . \&gerund;
        $value = $conjugate->($value);
        Log " => $value";
    }

    return $value;
}


