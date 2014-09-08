sub clear_cache {
    foreach my $channel ( keys %{$stats{users}} ) {
        next if $channel !~ /^#/;
        foreach my $user ( keys %{$stats{users}{$channel}} ) {
            delete $stats{users}{$channel}{$user}
              if $stats{users}{$channel}{$user}{last_active} <
              time - &config("user_activity_timeout");
        }
    }

    foreach my $chl ( keys %{$stats{last_talk}} ) {
        foreach my $user ( keys %{$stats{last_talk}{$chl}} ) {
            if ( not $stats{last_talk}{$chl}{$user}{when}
                or $stats{last_talk}{$chl}{$user}{when} >
                &config("user_activity_timeout") )
            {
                if ( $stats{last_talk}{$chl}{$user}{count} > 20 ) {
                    Report "Clearing flood flag for $user in $chl";
                }
                delete $stats{last_talk}{$chl}{$user};
            }
        }
    }
}


