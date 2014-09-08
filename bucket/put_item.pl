# here's the story.  put_item is called either when someone hands us a new
# item, or when a new item is crafted.  When handed items, we just refuse to go
# over the inventory_size, dropping at least one item before accepting the new
# one.
# But, crafted items can push us over the inventory_size to double that.  If a
# crafted item hits the hard limit (2x), do NOT accept it, instead, just drop.
# return values:
# -1 - duplicate item
# 1  - item accepted
# 2  - items dropped.  for handed items, the item has also been accepted.
sub put_item {
    my $item    = shift;
    my $crafted = shift;

    my $dup = 0;
    foreach my $inv_item (@inventory) {
        if ( lc $inv_item eq lc $item ) {
            $dup = 1;
            last;
        }
    }

    if ($dup) {
        return -1;
    } else {
        if (   ( $crafted and @inventory >= 2 * &config("inventory_size") )
            or ( not $crafted and @inventory >= &config("inventory_size") ) )
        {

            my $dropping_rate = &config("item_drop_rate");
            my @drop;
            while ( @inventory >= &config("inventory_size")
                and $dropping_rate-- > 0 )
            {
                push @drop, &get_item(1);
            }

            unless ($crafted) {
                push @inventory, $item;
            }

            return ( 2, @drop );
        } else {
            push @inventory, $item;
            return 1;
        }
    }
}


