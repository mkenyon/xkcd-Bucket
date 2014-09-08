sub expand {
    my ( $who, $chl, $msg, $editable, $to ) = @_;

    my $gender = $stats{users}{genders}{lc $who};
    my $target = $who;
    while ( $msg =~ /(?<!\\)(\$who\b|\${who})/i ) {
        my $cased = &set_case( $1, $who );
        last unless $msg =~ s/(?<!\\)(?:\$who\b|\${who})/$cased/i;
        $stats{last_vars}{$chl}{who} = $who;
    }

    if ( $msg =~ /(?<!\\)(?:\$someone\b|\${someone})/i ) {
        $stats{last_vars}{$chl}{someone} = [];
        while ( $msg =~ /(?<!\\)(\$someone\b|\${someone})/i ) {
            my $rnick = &someone( $chl, $who, defined $to ? $to : () );
            my $cased = &set_case( $1, $rnick );
            last unless $msg =~ s/\$someone\b|\${someone}/$cased/i;
            push @{$stats{last_vars}{$chl}{someone}}, $rnick;

            $gender = $stats{users}{genders}{lc $rnick};
            $target = $rnick;
        }
    }

    while ( $msg =~ /(?<!\\)(\$to\b|\${to})/i ) {
        unless ( defined $to ) {
            $to = &someone( $chl, $who );
        }
        my $cased = &set_case( $1, $to );
        last unless $msg =~ s/(?<!\\)(?:\$to\b|\${to})/$cased/i;
        push @{$stats{last_vars}{$chl}{to}}, $to;

        $gender = $stats{users}{genders}{lc $to};
        $target = $to;
    }

    $stats{last_vars}{$chl}{item} = [];
    while ( $msg =~ /(?<!\\)(\$(give)?item|\${(give)?item})/i ) {
        my $giveflag = $2 || $3 ? "give" : "";
        if (@inventory) {
            my $give  = $editable && $giveflag;
            my $item  = &get_item($give);
            my $cased = &set_case( $1, $item );
            push @{$stats{last_vars}{$chl}{item}},
              $give ? "$item (given)" : $item;
            last
              unless $msg =~
              s/(?<!\\)(?:\$${giveflag}item|\${${giveflag}item})/$cased/i;
        } else {
            $msg =~
              s/(?<!\\)(?:\$${giveflag}item|\${${giveflag}item})/bananas/i;
            push @{$stats{last_vars}{$chl}{item}}, "(bananas)";
        }
    }
    delete $stats{last_vars}{$chl}{item}
      unless @{$stats{last_vars}{$chl}{item}};

    $stats{last_vars}{$chl}{newitem} = [];
    while ( $msg =~ /(?<!\\)(\$(new|get)item|\${(new|get)item})/i ) {
        my $keep = lc( $2 || $3 );
        if ($editable) {
            my $newitem = shift @random_items || 'bananas';
            if ( $keep eq 'new' ) {
                my ( $rc, @dropped ) = &put_item( $newitem, 1 );
                if ( $rc == 2 ) {
                    $stats{last_vars}{$chl}{dropped} = \@dropped;
                    &cached_reply( $chl, $who, \@dropped, "drops item" );
                    return;
                }
            }

            if (@random_items <= &config("random_item_cache_size") / 2) {
              # force a cache update
              Log "Random item cache running low, forcing an update.";
              $stats{last_updated} = 0;
            }

            my $cased = &set_case( $1, $newitem );
            last
              unless $msg =~
              s/(?<!\\)(?:\$${keep}item|\${${keep}item})/$cased/i;
            push @{$stats{last_vars}{$chl}{newitem}}, $newitem;
        } else {
            $msg =~ s/(?<!\\)(?:\$${keep}item|\${${keep}item})/bananas/ig;
        }
    }
    delete $stats{last_vars}{$chl}{newitem}
      unless @{$stats{last_vars}{$chl}{newitem}};

    if ($gender) {
        foreach my $gvar ( keys %gender_vars ) {
            next unless $msg =~ /(?<!\\)(?:\$$gvar\b|\${$gvar})/i;

            Log "Replacing gvar $gvar...";
            if ( exists $gender_vars{$gvar}{$gender} ) {
                my $g_v = $gender_vars{$gvar}{$gender};
                Log " => $g_v";
                if ( $g_v =~ /%N/ ) {
                    $g_v =~ s/%N/$target/;
                    Log " => $g_v";
                }
                while ( $msg =~ /(?<!\\)(\$$gvar\b|\${$gvar})/i ) {
                    my $cased = &set_case( $1, $g_v );
                    last unless $msg =~ s/\Q$1/$cased/g;
                }
                $stats{last_vars}{$chl}{$gvar} = $g_v;
            } else {
                Log "Can't find gvar for $gvar->$gender!";
            }
        }
    }

    my $oldmsg = "";
    $stats{last_vars}{$chl} = {};
    while ( $oldmsg ne $msg
        and $msg =~ /(?<!\\)(?:\$([a-zA-Z_]\w+)|\${([a-zA-Z_]\w+)})/ )
    {
        $oldmsg = $msg;
        my $var = $1 || $2;
        Log "Found variable \$$var";

        # yay for special cases!
        my $conjugate;
        my $record = $replacables{lc $var};
        my $full   = $var;
        if ( not $record and $var =~ s/ed$//i ) {
            $record = $replacables{lc $var};
            if ( $record and $record->{type} eq 'verb' ) {
                $conjugate = \&past;
                Log "Special case *ed";
            } else {
                undef $record;
                $var = $full;
            }
        }

        if ( not $record and $var =~ s/ing$//i ) {
            $record = $replacables{lc $var};
            if ( $record and $record->{type} eq 'verb' ) {
                $conjugate = \&gerund;
                Log "Special case *ing";
            } else {
                undef $record;
                $var = $full;
            }
        }

        if ( not $record and $var =~ s/s$//i ) {
            $record = $replacables{lc $var};
            if ( $record and $record->{type} eq 'verb' ) {
                $conjugate = \&s_form;
                Log "Special case *s (verb)";
            } elsif ( $record and $record->{type} eq 'noun' ) {
                $conjugate = \&PL_N;
                Log "Special case *s (noun)";
            } else {
                undef $record;
                $var = $full;
            }
        }

        unless ($record) {
            Log "Can't find a record for \$$var";
            last;
        }

        $stats{last_vars}{$chl}{$full} = []
          unless exists $stats{last_vars}{$chl}{$full};
        Log "full = $full, msg = $msg";
        while ( $msg =~ /((\ban? )?(?<!\\)\$(?:$full|{$full})(?:\b|$))/i ) {
            my $replacement = &get_var( $record, $var, $conjugate );
            $replacement = &set_case( $var, $replacement );
            $replacement = A($replacement) if $2;

            if ( exists $record->{cache} and not @{$record->{cache}} ) {
                Log "Refilling cache for $full";
                &sql(
                    'select vars.id id, name, perms, type, value
                      from bucket_vars vars
                           left join bucket_values vals
                           on vars.id = vals.var_id
                      where name = ?
                      order by rand()
                      limit 20',
                    [$full],
                    {cmd => "load_vars_large", db_type => 'MULTIPLE'}
                );
            }

            if ( $2 and substr( $2, 0, 1 ) eq 'A' ) {
                $replacement = ucfirst $replacement;
            }

            Log "Replacing $1 with $replacement";
            last if $replacement =~ /\$/;

            $msg =~
              s/(?:\ban? )?(?<!\\)\$(?:$full|{$full})(?:\b|$)/$replacement/i;
            push @{$stats{last_vars}{$chl}{$full}}, $replacement;
        }

        Log " => $msg";
    }

    return $msg;
}


