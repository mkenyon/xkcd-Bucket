sub Log {
    print scalar localtime, " - @_\n";
    if ( &config("logfile") ) {
        print LOG scalar localtime, " - @_\n";
    }
}


