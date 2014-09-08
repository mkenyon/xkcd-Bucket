sub irc_on_public {
    my ($who) = split /!/, $_[ARG0];
    my $type  = $_[STATE];
    my $chl   = $_[ARG1];
    $chl = $chl->[0] if ref $chl eq 'ARRAY';
    my $msg = $_[ARG2];
    $msg =~ s/\s\s+/ /g;
    my %bag;

    $bag{who}  = $who;
    $bag{msg}  = $msg;
    $bag{chl}  = $chl;
    $bag{type} = $type;

    if ( not $stats{tail_time} or time - $stats{tail_time} > 60 ) {
        &tail( $_[KERNEL] );
        $stats{tail_time} = time;
    }

    $last_activity{$chl} = time;

    if ( exists $config->{ignore}{lc $bag{who}} ) {
        Log("ignoring $bag{who} in $bag{chl}");
        return;
    }

    $bag{addressed} = 0;
    if ( $type eq 'irc_msg' or $bag{msg} =~ s/^$nick[:,]\s*|,\s+$nick\W+$//i ) {
        $bag{addressed} = 1;
        $bag{to}        = $nick;
    } else {
        $bag{msg} =~ s/^(\S+):\s*//;
        $bag{to} = $1;
    }

    $bag{op} = 0;
    if (   $irc->is_channel_member( $channel, $bag{who} )
        or $irc->is_channel_operator( $mainchannel, $bag{who} )
        or $irc->is_channel_owner( $mainchannel, $bag{who} )
        or $irc->is_channel_admin( $mainchannel, $bag{who} ) )
    {
        $bag{op} = 1;
    }

    # allow editing only in public channels (other than #bots), or by ops.
    $bag{editable} = 1 if ( $chl =~ /^#/ and $chl ne '#bots' ) or $bag{op};

    if ( $type eq 'irc_msg' ) {
        return if &signal_plugin( "on_msg", \%bag );
    } else {
        return if &signal_plugin( "on_public", \%bag );
    }

    my $editable  = $bag{editable};
    my $addressed = $bag{addressed};
    my $operator  = $bag{op};
    $msg = $bag{msg};

    # keep track of who's active in each channel
    if ( $chl =~ /^#/ ) {
        $stats{users}{$chl}{$bag{who}}{last_active} = time;
    }

    unless ( exists $stats{users}{genders}{lc $bag{who}} ) {
        &load_gender( $bag{who} );
    }

    # flood protection
    if ( not $operator and $addressed ) {
        $stats{last_talk}{$chl}{$bag{who}}{when} = time;
        if ( $stats{last_talk}{$chl}{$bag{who}}{count}++ > 20
            and time - $stats{last_talk}{$chl}{$bag{who}}{when} <
            &config("user_activity_timeout") )
        {
            if ( $stats{last_talk}{$chl}{$bag{who}}{count} == 21 ) {
                Report "Ignoring $bag{who} who is flooding in $chl.";
                &say( $chl =>
                      "$bag{who}, I'm a bit busy now, try again in 5 minutes?"
                );
            }
            return;
        }
    }

    $bag{msg} =~ s/^\s+|\s+$//g;

    unless ( &talking($chl) == -1 or ( $operator and $addressed ) ) {
        my $timeout = &talking($chl);
        if ( $addressed and &config("increase_mute") and $timeout > 0 ) {
            &talking( $chl, $timeout + &config("increase_mute") );
            Report "Shutting up longer in $chl - "
              . ( &talking($chl) - time )
              . " seconds remaining";
        }
        return;
    }

    if ( time - $stats{last_updated} > 600 ) {
        &get_stats( $_[KERNEL] );
        &clear_cache();
        &random_item_cache( $_[KERNEL], 1 );
    }

    if ( $type eq 'irc_msg' ) {
        $bag{chl} = $chl = $bag{who};
    }

    Log(
"$type($chl): $bag{who}(o=$operator, a=$addressed, e=$editable): $bag{msg}"
    );

    # check all registered commands
    foreach my $cmd (@registered_commands) {
        if (    $addressed >= $cmd->{addressed}
            and $operator >= $cmd->{operator}
            and $editable >= $cmd->{editable}
            and $bag{msg} =~ $cmd->{re} )
        {
            Log("Matched cmd '$cmd->{label}' from $cmd->{plugin}.");
            $cmd->{callback}->( \%bag );
            return;
        }
    }

    if (
            $addressed
        and $editable
        and $bag{msg} =~ m{ (.*?)    # $1 key to edit
                   \s+(?:=~|~=)\s+   # match operator
                   s(\W)             # start match ($2 delimiter)
                     (               # $3 - string to replace
                       [^\2]+        # anything but a delimiter
                     )               # end of $3
                   \2                # separator
                    (.*)             # $4 - text to replace with
                   \2
                   ([gi]*)           # $5 - i/g flags
                   \s* $             # trailing spaces
                 }x
      )
    {
        my ( $fact, $old, $new, $flag ) = ( $1, $3, $4, $5 );
        Report
          "$bag{who} is editing $fact in $chl: replacing '$old' with '$new'";
        Log "Editing $fact: replacing '$old' with '$new'";
        if ( $fact =~ /^#(\d+)$/ ) {
            &sql(
                'select * from bucket_facts where id = ?',
                [$1],
                {
                    %bag,
                    cmd     => "edit",
                    old     => $old,
                    'new'   => $new,
                    flag    => $flag,
                    db_type => 'MULTIPLE',
                }
            );
        } else {
            &sql(
                'select * from bucket_facts where fact = ? order by id',
                [$fact],
                {
                    %bag,
                    cmd     => "edit",
                    fact    => $fact,
                    old     => $old,
                    'new'   => $new,
                    flag    => $flag,
                    db_type => 'MULTIPLE',
                }
            );
        }
    } elsif (
        $bag{msg} =~ m{ (.*?)             # $1 key to look up
                   \s+(?:=~|~=)\s+   # match operator
                   (\W)              # start match (any delimiter, $2)
                     (               # $3 - string to search
                       [^\2]+        # anything but a delimiter
                     )               # end of $3
                   \2                # same delimiter that opened the match
            }x
      )
    {
        my ( $fact, $search ) = ( $1, $3 );
        $fact = &trim($fact);
        $bag{msg} = $fact;
        Log "Looking up a particular factoid - '$search' in '$fact'";
        &lookup( %bag, search => $search, );
    } elsif ( $addressed and $operator and $bag{msg} =~ /^list plugins\W*$/i ) {
        &say(
            $chl => "$bag{who}: Currently loaded plugins: "
              . &make_list(
                map { "$_($stats{loaded_plugins}{$_})" }
                sort keys %{$stats{loaded_plugins}}
              )
        );
    } elsif ( $addressed
        and $operator
        and $bag{msg} =~ /^load plugin (\w+)\W*$/i )
    {
        if ( &load_plugin( lc $1 ) ) {
            &say( $chl => "Okay, $bag{who}. Plugin $1 loaded." );
        } else {
            &say( $chl => "Sorry, $bag{who}. Plugin $1 failed to load." );
        }
    } elsif ( $addressed
        and $operator
        and $bag{msg} =~ /^unload plugin (\w+)\W*$/i )
    {
        &unload_plugin( lc $1 );
        &say( $chl => "Okay, $bag{who}. Plugin $1 unloaded." );
    } elsif ( $addressed and $bag{msg} =~ /^literal(?:\[([*\d]+)\])?\s+(.*)/i )
    {
        my ( $page, $fact ) = ( $1 || 1, $2 );
        $stats{literal}++;
        $fact = &trim($fact);
        $fact = &decommify($fact);
        Log "Literal[$page] $fact";
        &sql(
            'select id, verb, tidbit, mood, chance, protected from
              bucket_facts where fact = ? order by id',
            [$fact],
            {
                %bag,
                cmd       => "literal",
                page      => $page,
                fact      => $fact,
                addressed => $addressed,
                db_type   => 'MULTIPLE',
            }
        );
    } elsif ( $addressed
        and $operator
        and $bag{msg} =~ /^delete item #?(\d+)\W*$/i )
    {
        unless ( $stats{detailed_inventory}{$bag{who}} ) {
            &say( $chl => "$bag{who}: ask me for a detailed inventory first." );
            return;
        }

        my $num  = $1 - 1;
        my $item = $stats{detailed_inventory}{$bag{who}}[$num];
        unless ( defined $item ) {
            &say( $chl => "Sorry, $bag{who}, I can't find that!" );
            return;
        }
        &say( $chl => "Okay, $bag{who}, destroying '$item'" );
        @inventory = grep { $_ ne $item } @inventory;
        &sql( "delete from bucket_items where `what` = ?", [$item] );
        delete $stats{detailed_inventory}{$bag{who}}[$num];
    } elsif ( $addressed and $operator and $bag{msg} =~ /^delete ((#)?.+)/i ) {
        my $id   = $2;
        my $fact = $1;
        $stats{deleted}++;

        if ($id) {
            while ( $fact =~ s/#(\d+)\s*// ) {
                &sql(
                    'select fact, tidbit, verb, RE, protected, mood, chance
                      from bucket_facts where id = ?',
                    [$1],
                    {
                        %bag,
                        cmd     => "delete_id",
                        fact    => $1,
                        db_type => "SINGLE",
                    }
                );
            }
        } else {
            &sql(
                'select fact, tidbit, verb, RE, protected, mood, chance from
                  bucket_facts where fact = ?',
                [$fact],
                {
                    %bag,
                    cmd     => "delete",
                    fact    => $fact,
                    db_type => 'MULTIPLE',
                }
            );
        }
    } elsif (
        $addressed
        and $bag{msg} =~ /^(?:shut \s up | go \s away)
                      (?: \s for \s (\d+)([smh])?|
                          \s for \s a \s (bit|moment|while|min(?:ute)?))?[.!]?$/xi
      )
    {
        $stats{shutup}++;
        my ( $num, $unit, $word ) = ( $1, lc $2, lc $3 );
        if ($operator) {
            my $target = 0;
            unless ( $num or $word ) {
                $num = 60 * 60;    # by default, shut up for one hour
            }
            if ($num) {
                $target += $num if not $unit or $unit eq 's';
                $target += $num * 60           if $unit eq 'm';
                $target += $num * 60 * 60      if $unit eq 'h';
                $target += $num * 60 * 60 * 24 if $unit eq 'd';
                Report
                  "Shutting up in $chl at ${who}'s request for $target seconds";
                &say( $chl => "Okay $bag{who}.  I'll be back later" );
                &talking( $chl, time + $target );
            } elsif ($word) {
                $target += 60 if $word eq 'min' or $word eq 'minute';
                $target += 30 + int( rand(60) )           if $word eq 'moment';
                $target += 4 * 60 + int( rand( 4 * 60 ) ) if $word eq 'bit';
                $target += 30 * 60 + int( rand( 30 * 60 ) ) if $word eq 'while';
                Report
                  "Shutting up in $chl at ${who}'s request for $target seconds";
                &say( $chl => "Okay $bag{who}.  I'll be back later" );
                &talking( $chl, time + $target );
            }
        } else {
            &say( $chl => "Okay, $bag{who} - be back in a bit!" );
            &talking( $chl, time + &config("timeout") );
        }
    } elsif ( $addressed
        and $operator
        and $bag{msg} =~ /^unshut up\W*$|^come back\W*$/i )
    {
        &say( $chl => "\\o/" );
        &talking( $chl, -1 );
    } elsif ( $addressed
        and $operator
        and $bag{msg} =~ /^(join|part) (#[-\w]+)(?: (.*))?/i )
    {
        my ( $cmd, $dst, $msg ) = ( $1, $2, $3 );
        unless ($dst) {
            &say( $chl => "$bag{who}: $cmd what channel?" );
            return;
        }
        $irc->yield( $cmd => $msg ? ( $dst, $msg ) : $dst );
        &say( $chl => "$bag{who}: ${cmd}ing $dst" );
        Report "${cmd}ing $dst at ${who}'s request";
    } elsif ( $addressed and $operator and lc $bag{msg} eq 'list ignored' ) {
        &say(
            $chl => "Currently ignored: ",
            join ", ", sort keys %{$config->{ignore}}
        );
    } elsif ( $addressed
        and $operator
        and $bag{msg} =~ /^([\w']+) has (\d+) syllables?\W*$/i )
    {
        $config->{sylcheat}{lc $1} = $2;
        &save;
        &say( $chl => "Okay, $bag{who}.  Cheat sheet updated." );
    } elsif ( $addressed and $operator and $bag{msg} =~ /^(un)?ignore (\S+)/i )
    {
        Report "$bag{who} is $1ignoring $2";
        if ($1) {
            delete $config->{ignore}{lc $2};
        } else {
            $config->{ignore}{lc $2} = 1;
        }
        &save;
        &say( $chl => "Okay, $bag{who}.  Ignore list updated." );
    } elsif ( $addressed and $operator and $bag{msg} =~ /^(un)?exclude (\S+)/i )
    {
        Report "$bag{who} is $1excluding $2";
        if ($1) {
            delete $config->{exclude}{lc $2};
        } else {
            $config->{exclude}{lc $2} = 1;
        }
        &save;
        &say( $chl => "Okay, $bag{who}.  Exclude list updated." );
    } elsif ( $addressed and $operator and $bag{msg} =~ /^(un)?protect (.+)/i )
    {
        my ( $protect, $fact ) = ( ( $1 ? 0 : 1 ), $2 );
        Report "$bag{who} is $1protecting $fact";
        Log "$1protecting $fact";

        if ( $fact =~ s/^\$// ) {    # it's a variable!
            unless ( exists $replacables{lc $fact} ) {
                &say( $chl =>
                      "Sorry, $bag{who}, \$$fact isn't a valid variable." );
                return;
            }

            $replacables{lc $fact}{perms} = $protect ? "read-only" : "editable";
        } else {
            &sql( 'update bucket_facts set protected=? where fact=?',
                [ $protect, $fact ] );
        }
        &say( $chl => "Okay, $bag{who}, updated the protection bit." );
    } elsif ( $addressed and $bag{msg} =~ /^undo last(?: (#\S+))?/ ) {
        Log "$bag{who} called undo:";
        my $uchannel = $1 || $chl;
        my $undo = $undo{$uchannel};
        unless ( $operator or $undo->[1] eq $bag{who} ) {
            &say( $chl => "Sorry, $bag{who}, you can't undo that." );
            return;
        }
        Log Dumper $undo;
        if ( $undo->[0] eq 'delete' ) {
            &sql(
                'delete from bucket_facts where id=? limit 1',
                [ $undo->[2] ],
            );
            Report "$bag{who} called undo: deleted $undo->[3].";
            &say( $chl => "Okay, $bag{who}, deleted $undo->[3]." );
            delete $undo{$uchannel};
        } elsif ( $undo->[0] eq 'insert' ) {
            if ( $undo->[2] and ref $undo->[2] eq 'ARRAY' ) {
                foreach my $entry ( @{$undo->[2]} ) {
                    my %old = %$entry;
                    $old{RE}        = 0 unless $old{RE};
                    $old{protected} = 0 unless $old{protected};
                    &sql(
                        'insert bucket_facts
                          (fact, verb, tidbit, protected, RE, mood, chance)
                          values(?, ?, ?, ?, ?, ?, ?)',
                        [ @old{qw/fact verb tidbit protected RE mood chance/} ],
                    );
                }
                Report "$bag{who} called undo: undeleted $undo->[3].";
                &say( $chl => "Okay, $bag{who}, undeleted $undo->[3]." );
            } elsif ( $undo->[2] and ref $undo->[2] eq 'HASH' ) {
                my %old = %{$undo->[2]};
                $old{RE}        = 0 unless $old{RE};
                $old{protected} = 0 unless $old{protected};
                &sql(
                    'insert bucket_facts
                      (id, fact, verb, tidbit, protected, RE, mood, chance)
                      values(?, ?, ?, ?, ?, ?, ?, ?)',
                    [ @old{qw/id fact verb tidbit protected RE mood chance/} ],
                );
                Report "$bag{who} called undo:",
                  "unforgot $old{fact} $old{verb} $old{tidbit}.";
                &say( $chl =>
"Okay, $bag{who}, unforgot $old{fact} $old{verb} $old{tidbit}."
                );
            } else {
                &say( $chl =>
                        "Sorry, $bag{who}, that's an invalid undo structure."
                      . "  Tell Zigdon, please." );
            }

        } elsif ( $undo->[0] eq 'edit' ) {
            if ( $undo->[2] and ref $undo->[2] eq 'ARRAY' ) {
                foreach my $entry ( @{$undo->[2]} ) {
                    if ( $entry->[0] eq 'update' ) {
                        &sql(
                            'update bucket_facts set verb=?, tidbit=?
                              where id=? limit 1',
                            [ $entry->[2], $entry->[3], $entry->[1] ],
                        );
                    } elsif ( $entry->[0] eq 'insert' ) {
                        my %old = %{$entry->[1]};
                        $old{RE}        = 0 unless $old{RE};
                        $old{protected} = 0 unless $old{protected};
                        &sql(
                            'insert bucket_facts
                              (fact, verb, tidbit, protected, RE, mood, chance)
                              values(?, ?, ?, ?, ?, ?, ?)',
                            [
                                @old{
                                    qw/fact verb tidbit protected RE mood chance/
                                }
                            ],
                        );
                    }
                }
                Report "$bag{who} called undo: undone $undo->[3].";
                &say( $chl => "Okay, $bag{who}, undone $undo->[3]." );
            } else {
                &say( $chl =>
                        "Sorry, $bag{who}, that's an invalid undo structure."
                      . "  Tell Zigdon, please." );
            }
            delete $undo{$uchannel};
        } else {
            &say( $chl => "Sorry, $bag{who}, can't undo $undo->[0] yet" );
        }
    } elsif ( $addressed and $operator and $bag{msg} =~ /^merge (.*) => (.*)/ )
    {
        my ( $src, $dst ) = ( $1, $2 );
        $stats{merge}++;

        &sql(
            'select id, verb, tidbit from bucket_facts where fact = ? limit 1',
            [$src],
            {
                %bag,
                cmd     => "merge",
                src     => $src,
                dst     => $dst,
                db_type => "SINGLE",
            }
        );
    } elsif ( $addressed and $operator and $bag{msg} =~ /^alias (.*) => (.*)/ )
    {
        my ( $src, $dst ) = ( $1, $2 );
        $stats{alias}++;

        &sql(
            'select id, verb, tidbit from bucket_facts where fact = ? limit 1',
            [$src],
            {
                %bag,
                cmd     => "alias1",
                src     => $src,
                dst     => $dst,
                db_type => "SINGLE",
            }
        );
    } elsif ( $operator and $addressed and $bag{msg} =~ /^lookup #?(\d+)\W*$/ )
    {
        &sql(
            'select id, fact, verb, tidbit from bucket_facts where id = ? ',
            [$1],
            {
                %bag,
                msg       => undef,
                cmd       => "fact",
                addressed => 0,
                editable  => 0,
                op        => 0,
                db_type   => "SINGLE",
            }
        );
    } elsif ( $operator
        and $addressed
        and $bag{msg} =~ /^forget (?:that|#(\d+))\W*$/ )
    {
        my $id = $1 || $stats{last_fact}{$chl};
        unless ($id) {
            &say( $chl => "Sorry, $bag{who}, forget what?" );
            return;
        }

        &sql( 'select * from bucket_facts where id = ?',
            [$id], {%bag, cmd => "forget", id => $id, db_type => "SINGLE",} );
    } elsif ( $addressed and $bag{msg} =~ /^what was that\??$/i ) {
        my $id = $stats{last_fact}{$chl};
        unless ($id) {
            &say( $chl => "Sorry, $bag{who}, I have no idea." );
            return;
        }

        if ( $id =~ /^(\d+)$/ ) {
            &sql( 'select * from bucket_facts where id = ?',
                [$id],
                {%bag, cmd => "report", id => $id, db_type => "SINGLE",} );
        } else {
            &say( $chl => "$bag{who}: that was $id" );
        }
    } elsif ( $addressed and $bag{msg} eq 'something random' ) {
        &lookup(%bag);
    } elsif ( $addressed and $bag{msg} eq 'stats' ) {
        unless ( $stats{stats_cached} ) {
            &say( $chl => "$bag{who}: Hold on, I'm still counting" );
            return;
        }

        # get the last modified time for any bit of the code
        my $mtime = ( stat($0) )[9];
        my $dir   = &config("plugin_dir");
        if ( $dir and opendir( PLUGINS, $dir ) ) {
            foreach my $file ( readdir(PLUGINS) ) {
                next unless $file =~ /^plugin\.\w+\.pl$/;
                if ( $mtime < ( stat("$dir/$file") )[9] ) {
                    $mtime = ( stat(_) )[9];
                }
            }
            closedir PLUGINS;
        }

        my ( $mod,   $modu )  = &round_time( time - $mtime );
        my ( $awake, $units ) = &round_time( time - $stats{startup_time} );

        my $reply;
        $reply = sprintf "I've been awake since %s (about %d %s), ",
          scalar localtime( $stats{startup_time} ),
          $awake, $units;

        if ( $awake != $mod or $units ne $modu ) {
            if ( ( stat($0) )[9] < $stats{startup_time} ) {
                $reply .= sprintf "and was last changed about %d %s ago. ",
                  $mod, $modu;
            } else {
                $reply .=
                  sprintf "and a newer version has been available for %d %s. ",
                  $mod, $modu;
            }
        } else {
            $reply .= "and that was when I was last changed. ";
        }

        if ( $stats{learn} + $stats{edited} + $stats{deleted} ) {
            $reply .= "Since waking up, I've ";
            my @fact_stats;
            push @fact_stats,
              sprintf "learned %d new factoid%s",
              $stats{learn}, &s( $stats{learn} )
              if ( $stats{learn} );
            push @fact_stats,
              sprintf "updated %d factoid%s", $stats{edited},
              &s( $stats{edited} )
              if ( $stats{edited} );
            push @fact_stats,
              sprintf "forgot %d factoid%s",
              $stats{deleted}, &s( $stats{deleted} )
              if ( $stats{deleted} );
            push @fact_stats, sprintf "found %d haiku", $stats{haiku}
              if ( $stats{haiku} );

            # strip out the string 'factoids' from all but the first entry
            if ( @fact_stats > 1 ) {
                s/ factoids?// foreach @fact_stats[ 1 .. $#fact_stats ];
            }

            if (@fact_stats) {
                $reply .= &make_list(@fact_stats) . ". ";
            } else {
                $reply .= "haven't had a chance to do much!";
            }
        }
        $reply .= sprintf "I know now a total of %s thing%s "
          . "about %s subject%s. ",
          &commify( $stats{rows} ),     &s( $stats{rows} ),
          &commify( $stats{triggers} ), &s( $stats{triggers} );
        $reply .=
          sprintf "I know of %s object%s" . " and am carrying %d of them. ",
          &commify( $stats{items} ), &s( $stats{items} ), scalar @inventory;
        if ( &talking($chl) == 0 ) {
            $reply .= "I'm being quiet right now. ";
        } elsif ( &talking($chl) > 0 ) {
            $reply .=
              sprintf "I'm being quiet right now, "
              . "but I'll be back in about %s %s. ",
              &round_time( &talking($chl) - time );
        }
        &say( $chl => $reply );
    } elsif ( $operator and $addressed and $bag{msg} =~ /^stat (\w+)\??/ ) {
        my $key = $1;
        if ( $key eq 'keys' ) {
            &say_long( $chl => "$bag{who}: valid keys are: "
                  . &make_list( sort keys %stats )
                  . "." );
        } elsif ( exists $stats{$key} ) {
            if ( ref $stats{$key} ) {
                my $dump = Dumper( $stats{$key} );
                $dump =~ s/[\s\n]+/ /g;
                &say( $chl => "$bag{who}: $key: $dump." );
                Log $dump;
            } else {
                &say( $chl => "$bag{who}: $key: $stats{$key}." );
            }
        } else {
            &say( $chl =>
                  "Sorry, $bag{who}, I don't have statistics for '$key'." );
        }
    } elsif ( $operator and $addressed and $bag{msg} eq 'restart' ) {
        Report "Restarting at ${who}'s request";
        Log "Restarting at ${who}'s request";
        &say( $chl => "Okay, $bag{who}, I'll be right back." );
        $irc->yield( quit => "OHSHI--" );
    } elsif ( $operator
        and $addressed
        and $bag{msg} =~ /^set(?: (\w+) (.*)|$)/ )
    {
        my ( $key, $val ) = ( $1, $2 );

        unless ( $key and exists $config_keys{$key} ) {
            &say_long( $chl => "$bag{who}: Valid keys are: "
                  . &make_list( sort keys %config_keys ) );
            return;
        }

        if ( $config_keys{$key}[0] eq 'p' and $val =~ /^(\d+)%?$/ ) {
            $config->{$key} = $1;
        } elsif ( $config_keys{$key}[0] eq 'i' and $val =~ /^(\d+)$/ ) {
            $config->{$key} = $1;
        } elsif ( $config_keys{$key}[0] eq 's' ) {
            $val =~ s/^\s+|\s+$//g;
            $config->{$key} = $val;
        } elsif ( $config_keys{$key}[0] eq 'b' and $val =~ /^(true|false)$/ ) {
            $config->{$key} = $val eq 'true';
        } elsif ( $config_keys{$key}[0] eq 'f' and length $val ) {
            if ( -f $val ) {
                &say( $chl => "Sorry, $bag{who}, $val already exists." );
                return;
            } else {
                $config->{$key} = $val;
            }
        } else {
            &say(
                $chl => "Sorry, $bag{who}, that's an invalid value for $key." );
            return;
        }

        &say( $chl => "Okay, $bag{who}." );
        Report "$bag{who} set '$key' to '$val'";

        &save;
        return;
    } elsif ( $operator and $addressed and $bag{msg} =~ /^get (\w+)\W*$/ ) {
        my ($key) = ($1);
        unless ( exists $config_keys{$key} ) {
            &say_long( $chl => "$bag{who}: Valid keys are: "
                  . &make_list( sort keys %config_keys ) );
            return;
        }

        &say( $chl => "$key is", &config("$key") . "." );
    } elsif ( $addressed and $bag{msg} eq 'list vars' ) {
        unless ( keys %replacables ) {
            &say( $chl => "Sorry, $bag{who}, there are no defined variables!" );
            return;
        }
        &say(
            $chl => "Known variables:",
            &make_list(
                map {
                        $replacables{$_}->{type} eq 'noun' ? "$_(n)"
                      : $replacables{$_}->{type} eq 'verb' ? "$_(v)"
                      : $_
                  }
                  sort keys %replacables
              )
              . "."
        );
    } elsif ( $addressed and $bag{msg} =~ /^list var (\w+)$/ ) {
        my $var = $1;
        unless ( exists $replacables{$var} ) {
            &say( $chl => "Sorry, $bag{who}, I don't know a variable '$var'." );
            return;
        }

        unless (
            $replacables{$var}{cache}
            or ( ref $replacables{$var}{vals} eq 'ARRAY'
                and @{$replacables{$var}{vals}} )
          )
        {
            &say( $chl => "$bag{who}: \$$var has no values defined!" );
            return;
        }

        if ( exists $replacables{$var}{cache}
            or ref $replacables{$var}{vals} eq 'ARRAY'
            and @{$replacables{$var}{vals}} > 30 )
        {
            if ( &config("www_root") ) {
                &sql(
                    'select value
                      from bucket_vars vars
                           left join bucket_values vals
                           on vars.id = vals.var_id
                      where name = ?
                      order by value',
                    [$var],
                    {
                        %bag,
                        cmd     => "dump_var",
                        name    => $var,
                        db_type => 'MULTIPLE',
                    }
                );
            } else {
                &say( $chl =>
                      "Sorry, $bag{who}, I can't print $replacables{$var}{vals}"
                      . "values to the channel." );
            }
            return;
        }

        my @vals = @{$replacables{$var}{vals}};
        &say( $chl => "$var:", &make_list( sort @vals ) );
    } elsif ( $addressed and $bag{msg} =~ /^remove value (\w+) (.+)$/ ) {
        my ( $var, $value ) = ( lc $1, lc $2 );
        unless ( exists $replacables{$var} ) {
            &say( $chl =>
                  "Sorry, $bag{who}, I don't know of a variable '$var'." );
            return;
        }

        if ( $replacables{$var}{perms} ne "editable" and not $operator ) {
            &say( $chl =>
                  "Sorry, $bag{who}, you don't have permissions to edit '$var'."
            );
            return;
        }

        my $key = "vals";
        if ( exists $replacables{$var}{cache} ) {
            $key = "cache";

            &sql(
                "delete from bucket_values where var_id=? and value=? limit 1",
                [ $replacables{$var}{id}, $value ]
            );
            &say( $chl => "Okay, $bag{who}." );
            Report "$bag{who} removed a value from \$$var in $chl: $value";
        }

        foreach my $i ( 0 .. @{$replacables{$var}{$key}} - 1 ) {
            next unless lc $replacables{$var}{$key}[$i] eq $value;

            Log "found!";
            splice( @{$replacables{$var}{vals}}, $i, 1, () );

            return if ( $key eq 'cache' );

            &say( $chl => "Okay, $bag{who}." );
            Report "$bag{who} removed a value from \$$var in $chl: $value";
            &sql(
                "delete from bucket_values where var_id=? and value=? limit 1",
                [ $replacables{$var}{id}, $value ]
            );

            return;
        }

        return if $key eq 'cache';

        &say( $chl => "$bag{who}, '$value' isn't a valid value for \$$var!" );
    } elsif ( $addressed and $bag{msg} =~ /^add value (\w+) (.+)$/ ) {
        my ( $var, $value ) = ( lc $1, $2 );
        unless ( exists $replacables{$var} ) {
            &say( $chl =>
                  "Sorry, $bag{who}, I don't know of a variable '$var'." );
            return;
        }

        if ( $replacables{$var}{perms} ne "editable" and not $operator ) {
            &say( $chl =>
                  "Sorry, $bag{who}, you don't have permissions to edit '$var'."
            );
            return;
        }

        if ( $value =~ /\$/ ) {
            &say( $chl => "Sorry, $bag{who}, no nested values please." );
            return;
        }

        foreach my $v ( @{$replacables{$var}{vals}} ) {
            next unless lc $v eq lc $value;

            &say( $chl => "$bag{who}, I had it that way!" );
            return;
        }

        if ( exists $replacables{$var}{vals} ) {
            push @{$replacables{$var}{vals}}, $value;
        } else {
            push @{$replacables{$var}{cache}}, $value;
        }
        &say( $chl => "Okay, $bag{who}." );
        Report "$bag{who} added a value to \$$var in $chl: $value";

        &sql( "insert into bucket_values (var_id, value) values (?, ?)",
            [ $replacables{$var}{id}, $value ] );
    } elsif ( $operator
        and $addressed
        and $bag{msg} =~ /^create var (\w+)\W*$/ )
    {
        my $var = $1;
        if ( exists $replacables{$var} ) {
            &say( $chl =>
                  "Sorry, $bag{who}, there already exists a variable '$var'." );
            return;
        }

        $replacables{$var} = {vals => [], perms => "read-only", type => "var"};
        Log "$bag{who} created a new variable '$var' in $chl";
        Report "$bag{who} created a new variable '$var' in $chl";
        $undo{$chl} = [ 'newvar', $bag{who}, $var, "new variable '$var'." ];
        &say( $chl => "Okay, $bag{who}." );

        &sql( 'insert into bucket_vars (name, perms) values (?, "read-only")',
            [$var], {cmd => "create_var", var => $var} );
    } elsif ( $operator
        and $addressed
        and $bag{msg} =~ /^remove var (\w+)\s*(!+)?$/ )
    {
        my $var = $1;
        unless ( exists $replacables{$var} ) {
            &say( $chl => "Sorry, $bag{who}, there isn't a variable '$var'!" );
            return;
        }

        if ( exists $replacables{$var}{cache} and not $2 ) {
            &say( $chl =>
"$bag{who}, this action cannot be undone.  If you want to proceed "
                  . "append a '!'" );

            return;
        }

        if ( exists $replacables{$var}{vals} ) {
            $undo{$chl} = [
                'delvar', $bag{who}, $var, $replacables{$var},
                "deletion of variable '$var'."
            ];
            &say(
                $chl => "Okay, $bag{who}, removed variable \$$var with",
                scalar @{$replacables{$var}{vals}}, "values."
            );
        } else {
            &say( $chl => "Okay, $bag{who}, removed variable \$$var." );
        }

        &sql( "delete from bucket_values where var_id = ?",
            [ $replacables{$var}{id} ] );
        &sql( "delete from bucket_vars where id = ?",
            [ $replacables{$var}{id} ] );
        delete $replacables{$var};
    } elsif ( $operator
        and $addressed
        and $bag{msg} =~ /^var (\w+) type (var|verb|noun)\W*$/ )
    {
        my ( $var, $type ) = ( $1, $2 );
        unless ( exists $replacables{$var} ) {
            &say( $chl => "Sorry, $bag{who}, there isn't a variable '$var'!" );
            return;
        }

        Log "$bag{who} set var $var type to $type";
        &say( $chl => "Okay, $bag{who}" );
        $replacables{$var}{type} = $type;
        &sql( "update bucket_vars set type=? where id = ?",
            [ $type, $replacables{$var}{id} ] );
    } elsif ( $operator
        and $addressed
        and $bag{msg} =~ /^(?:detailed inventory|list item details)[?.!]?$/i )
    {
        unless (@inventory) {
            &say( $chl => "Sorry, $bag{who}, I'm not carrying anything!" );
            return;
        }
        $stats{detailed_inventory}{$bag{who}} = [];
        my $line;
        push @{$stats{detailed_inventory}{$bag{who}}}, sort @inventory;
        my $c = 1;
        &say_long(
            $chl => "$bag{who}: " . join "; ",
            map { $c++ . ": $_" } @{$stats{detailed_inventory}{$bag{who}}}
        );
    } elsif ( $addressed and $bag{msg} =~ /^(?:inventory|list items)[?.!]?$/i )
    {
        &cached_reply( $chl, $bag{who}, "", "list items" );
    } elsif (
        $addressed
        and $bag{msg} =~ /^(?:(I|[-\w]+) \s (?:am|is)|
                         I'm(?: an?)?) \s
                       (
                         male          |
                         female        |
                         androgynous   |
                         inanimate     |
                         full \s name  |
                         random gender
                       )\.?$/ix
        or $bag{msg} =~ / ^(I|[-\w]+) \s (am|is) \s an? \s
                       ( he | she | him | her | it )\.?$
                     /ix
      )
    {
        my ( $target, $gender, $pronoun ) = ( $1, $2, $3 );
        if (    uc $target ne "I"
            and lc $target ne lc $bag{who}
            and not $operator )
        {
            &say( $chl =>
                  "$bag{who}, you should let $target set their own gender." );
            return;
        }

        $target = $bag{who} if uc $target eq 'I';

        if ($pronoun) {
            $gender = undef;
            $gender = "male" if $pronoun eq 'him' or $pronoun eq 'he';
            $gender = "female" if $pronoun eq 'her' or $pronoun eq 'she';
            $gender = "inanimate" if $pronoun eq 'it';

            unless ($gender) {
                &say( $chl => "Sorry, $bag{who}, I didn't understand that." );
                return;
            }
        }

        Log "$bag{who} set ${target}'s gender to $gender";
        $stats{users}{genders}{lc $target} = lc $gender;
        &sql( "replace genders (nick, gender, stamp) values (?, ?, ?)",
            [ $target, $gender, undef ] );
        &say( $chl => "Okay, $bag{who}" );
    } elsif ( $addressed
        and $bag{msg} =~ /^what is my gender\??$|^what gender am I\??/i )
    {
        if ( exists $stats{users}{genders}{lc $bag{who}} ) {
            &say(
                $chl => "$bag{who}: Grammatically, I refer to you as",
                $stats{users}{genders}{lc $bag{who}} . ".  See",
                "http://wiki.xkcd.com/irc/Bucket#Docs for information on",
                "setting this."
            );

        } else {
            &load_gender( $bag{who} );
            &say( $chl => "$bag{who}: I don't know how to refer to you!" );
        }
    } elsif ( $addressed and $bag{msg} =~ /^what gender is ([-\w]+)\??$/i ) {
        if ( exists $stats{users}{genders}{lc $1} ) {
            &say( $chl => "$bag{who}: $1 is $stats{users}{genders}{lc $1}." );
        } else {
            &load_gender($1);
            &say( $chl => "$bag{who}: I don't know how to refer to $1!" );
        }
    } elsif ( $bag{msg} =~ /^uses(?: \S+){1,5}$/i
        and &config("uses_reply")
        and rand(100) < &config("uses_reply") )
    {
        &cached_reply( $chl, $bag{who}, undef, "uses reply" );
    } elsif ( &config("lookup_tla") > 0
        and rand(100) < &config("lookup_tla")
        and $bag{msg} =~ /^([A-Z])([A-Z])([A-Z])\??$/ )
    {
        my $pattern = "$1% $2% $3%";
        &sql(
            'select value
              from bucket_values
                   left join bucket_vars
                   on var_id = bucket_vars.id
              where name = ?  and value like ?
              order by rand()
              limit 1',
            [ &config("band_var"), $pattern ],
            {%bag, cmd => "tla", tla => $bag{msg}, db_type => 'SINGLE',}
        );
    } else {
        my $orig = $bag{msg};
        $bag{msg} = &trim( $bag{msg} );
        if (   $addressed
            or length $bag{msg} >= &config("minimum_length")
            or $bag{msg} eq '...' )
        {
            if ( $addressed and length $bag{msg} == 0 ) {
                $bag{msg} = $nick;
            }

            if (    not $operator
                and $type eq 'irc_public'
                and &config("repeated_queries") > 0 )
            {
                unless ( $stats{users}{$chl}{$bag{who}}{last_lookup} ) {
                    $stats{users}{$chl}{$bag{who}}{last_lookup} =
                      [ $bag{msg}, 0 ];
                }

                if ( $stats{users}{$chl}{$bag{who}}{last_lookup}[0] eq
                    $bag{msg} )
                {
                    if ( ++$stats{users}{$chl}{$bag{who}}{last_lookup}[1] ==
                        &config("repeated_queries") )
                    {
                        Report "Volunteering a dump of '$bag{msg}' for" .
                               " $bag{who} in $chl (if it exists)";
                        &sql(
                            'select id, verb, tidbit, mood, chance, protected
                              from bucket_facts where fact = ? order by id',
                            [ $bag{msg} ],
                            {
                                %bag,
                                cmd     => "literal",
                                page    => "*",
                                fact    => $bag{msg},
                                db_type => 'MULTIPLE',
                            }
                        );
                        return;
                    } elsif ( $stats{users}{$chl}{$bag{who}}{last_lookup}[1] >
                        &config("repeated_queries") )
                    {
                        Log "Ignoring $bag{who} who is asking '$bag{msg}'" .
                            " in $chl";
                        return;
                    }
                } else {
                    $stats{users}{$chl}{$bag{who}}{last_lookup} =
                      [ $bag{msg}, 1 ];
                }
            }

            &lookup( %bag, orig => $orig );
        }
    }
}

