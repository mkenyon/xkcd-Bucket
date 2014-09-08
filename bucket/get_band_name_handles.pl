sub get_band_name_handles {
    if ( exists $handles{dbh} ) {
        return \%handles;
    }

    Log "Creating band name database/query handles";
    unless ( $handles{dbh} ) {
        $handles{dbh} =
          DBI->connect( &config("db_dsn"), &config("db_username"),
            &config("db_password") )
          or Report "Failed to create dbh!" and return undef;
    }

    $handles{lookup} = $handles{dbh}->prepare(
        "select id, word, `lines`
         from word2id
         where word in (?, ?, ?)
         order by `lines`"
    );

    return \%handles;
}


