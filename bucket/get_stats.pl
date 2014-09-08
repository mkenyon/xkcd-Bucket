sub get_stats {
    my ($kernel) = @_;

    Log "Updating stats";
    &sql( 'select count(distinct fact) c from bucket_facts',
        undef, {cmd => 'stats1', db_type => 'SINGLE'} );
    &sql( 'select count(id) c from bucket_facts',
        undef, {cmd => 'stats2', db_type => 'SINGLE'} );
    &sql( 'select count(id) c from bucket_items',
        undef, {cmd => 'stats3', db_type => 'SINGLE'} );

    $stats{last_updated} = time;

    # check if the log file was moved, if so, reopen it
    if ( &config("logfile") and not -f &config("logfile") ) {
        &open_log;
        Log "Reopened log file";
    }
}


