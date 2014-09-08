sub open_log {
    if ( &config("logfile") ) {
        my $logfile =
          &DEBUG ? &config("logfile") . ".debug" : &config("logfile");
        open( LOG, ">>", $logfile )
          or die "Can't write " . &config("logfile") . ": $!";
        Log("Opened $logfile");
        print STDERR scalar localtime, " - @_\n";
        print STDERR "Logfile opened: $logfile.\n";
    }
}


