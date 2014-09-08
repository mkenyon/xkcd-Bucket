sub inventory {
    return "nothing" unless @inventory;

    return &make_list(@inventory);
}


