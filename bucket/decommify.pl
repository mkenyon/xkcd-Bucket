sub decommify {
    my $string = shift;

    $string =~ s/\s*,\s*/ /g;
    $string =~ s/\s\s+/ /g;

    return $string;
}
