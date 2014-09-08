sub sql {
    my ( $sql, $placeholders, $baggage ) = @_;

    my $type = $baggage->{db_type} || "DO";
    delete $baggage->{db_type};

    POE::Kernel->post(
        db    => $type,
        SQL   => $sql,
        EVENT => 'db_success',
        $placeholders ? ( PLACEHOLDERS => $placeholders ) : (),
        $baggage      ? ( BAGGAGE      => $baggage )      : (),
    );
}

