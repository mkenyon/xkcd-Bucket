sub validate_factoid {
    my $bag = shift;

    return 1 if $bag->{op};

    if ( &config("var_limit") > 0 ) {
        my $l = &config("var_limit");
        if ( $bag->{tidbit} =~ /(?:(?<!\\)\$[a-zA-Z_].+){$l}/ ) {
            Report("Too many variables in $bag->{tidbit}");
            return 0;
        }
    }

    return 1;
}

