sub get_item {
    my $give = shift;

    my $item = rand @inventory;
    if ($give) {
        Log "Dropping $inventory[$item]";
        return splice( @inventory, $item, 1, () );
    } else {
        return $inventory[$item];
    }
}


