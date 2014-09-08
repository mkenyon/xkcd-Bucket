sub commify {
    my $num = shift;
    1 while ( $num =~ s/(\d)(\d\d\d)\b/$1,$2/ );
    return $num;
}

