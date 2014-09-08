sub read_rss {
    my ( $url, $re, $tag ) = @_;

    eval {
        require LWP::Simple;
        import LWP::Simple qw/$ua/;
        require XML::Simple;

        $LWP::Simple::ua->agent("Bucket/$nick");
        $LWP::Simple::ua->timeout(10);
        my $rss = LWP::Simple::get($url);
        if ($rss) {
            Log "Retrieved RSS";
            my $xml = XML::Simple::XMLin($rss);
            for ( 1 .. 5 ) {
                if ( $xml and my $story = $xml->{channel}{item}[ rand(40) ] ) {
                    $story->{description} =
                      HTML::Entities::decode_entities( $story->{description} );
                    $story->{description} =~ s/$re//isg if $re;
                    next if $url =~ /twitter/ and $story->{description} =~ /^@/;
                    next if length $story->{description} > 400;
                    next if $story->{description} =~ /\[\.\.\.\]/;

                    return ( $story->{description}, $story->{$tag} );
                }
            }
        }
    };

    if ($@) {
        Report "Failed when trying to read RSS from $url: $@";
        return ();
    }
}


