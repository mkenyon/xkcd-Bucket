sub round_time {
    my $dt    = shift;
    my $units = "second";

    if ( $dt > 60 ) {
        $dt /= 60;    # minutes
        $units = "minute";

        if ( $dt > 60 ) {
            $dt /= 60;    # hours
            $units = "hour";

            if ( $dt > 24 ) {
                $dt /= 24;    # days
                $units = "day";

                if ( $dt > 7 ) {
                    $dt /= 7;    # weeks
                    $units = "week";
                }
            }
        }
    }
    $dt = int($dt);

    $units .= &s($dt);

    return ( $dt, $units );
}


