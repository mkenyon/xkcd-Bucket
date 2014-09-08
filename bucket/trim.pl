sub trim {
    my $msg = shift;

    $msg =~ s/[^\w+]+$// if $msg !~ /^[^\w+]+$/;
    $msg =~ s/\\(.)/$1/g;

    return $msg;
}


