sub tail {
    my $kernel = shift;

    my $time = 1;
    while (<BLOG>) {
        chomp;
        s/^[\d-]+ [\d:]+ //;
        s/from [\d.]+ //;
        Report $time++, $_;
    }
    seek BLOG, 0, SEEK_CUR;
}


