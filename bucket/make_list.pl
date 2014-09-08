sub make_list {
    my @list = @_;

    return "[none]" unless @list;
    return $list[0] if @list == 1;
    return join " and ", @list if @list == 2;
    my $last = $list[-1];
    return join( ", ", @list[ 0 .. $#list - 1 ] ) . ", and $last";
}

