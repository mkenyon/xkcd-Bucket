sub talking {

    # == 0 - shut up by operator
    # == -1 - talking
    # > 0 - shut up by user, until time()
    my ( $chl, $set ) = @_;

    if ($set) {
        return $_talking{$chl} = $set;
    } else {
        $_talking{$chl} = -1 unless exists $_talking{$chl};
        $_talking{$chl} = -1
          if ( $_talking{$chl} > 0 and $_talking{$chl} < time );
        return $_talking{$chl};
    }
}


