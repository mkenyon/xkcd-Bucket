sub db_success {
    my $res = $_[ARG0];

    foreach ( keys %$res ) {
        if (    $_ eq 'RESULT'
            and ref $res->{RESULT} eq 'ARRAY'
            and @{$res->{RESULT}} > 50 )
        {
            print "RESULT: ", scalar @{$res->{RESULT}}, "\n";
        } else {
            print "$_:\n", Dumper $res->{$_} if /BAGGAGE|PLACEHOLDERS|RESULT/;
        }
    }
    my %bag = ref $res->{BAGGAGE} ? %{$res->{BAGGAGE}} : ();
    if ( $res->{ERROR} ) {

        if ( $res->{ERROR} eq 'Lost connection to the database server.' ) {
            Report "DB Error: $res->{ERROR}  Restarting.";
            Log "DB Error: $res->{ERROR}";
            &say( $channel => "Database lost.  Self-destruct initiated." );
            $irc->yield( quit => "Eep, the house is on fire!" );
            return;
        }
        Report "DB Error: $res->{QUERY} -> $res->{ERROR}";
        Log "DB Error: $res->{QUERY} -> $res->{ERROR}";
        if ( $bag{chl} and $bag{addressed} ) {
            &say( $bag{chl} =>
                  "Something is terribly wrong. I'll be back later." );
            &say( $channel =>
"Something's wrong with the database. Shutting up in $bag{chl} for an hour."
            );
            &talking( $bag{chl}, time + 60 * 60 );
        }
        return;
    }

    return unless $bag{cmd};

    return if &signal_plugin( "db_success", {bag => \%bag, res => $res} );

    if ( $bag{cmd} eq 'fact' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        if ( defined $line{tidbit} ) {

            if ( $line{verb} eq '<alias>' ) {
                if ( $bag{aliases}{$line{tidbit}} ) {
                    Report "Alias loop detected when '$line{fact}'"
                      . " is aliased to '$line{tidbit}'";
                    Log "Alias loop detected when '$line{fact}'"
                      . " is aliased to '$line{tidbit}'";
                    &error( $bag{chl}, $bag{who} );
                    return;
                }
                $bag{aliases}{$line{tidbit}} = 1;
                $bag{alias_chain} .= "'$line{fact}' => ";

                Log "Following alias '$line{fact}' -> '$line{tidbit}'";
                &lookup( %bag, msg => $line{tidbit} );
                return;
            }

            $bag{msg}  = $line{fact} unless defined $bag{msg};
            $bag{orig} = $line{fact} unless defined $bag{orig};

            $stats{last_vars}{$bag{chl}}        = {};
            $stats{last_fact}{$bag{chl}}        = $line{id};
            $stats{last_alias_chain}{$bag{chl}} = $bag{alias_chain};
            $stats{lookup}++;

         # if we're just idle chatting, replace any $who reference with $someone
            if ( $bag{idle} ) {
                $bag{who} = &someone( $bag{chl} );
            }

            $line{tidbit} =
              &expand( $bag{who}, $bag{chl}, $line{tidbit}, $bag{editable},
                $bag{to} );
            return unless $line{tidbit};

            if ( $line{verb} eq '<reply>' ) {
                &say( $bag{chl} => $line{tidbit} );
            } elsif ( $line{verb} eq '\'s' ) {
                &say( $bag{chl} => "$bag{orig}'s $line{tidbit}" );
            } elsif ( $line{verb} eq '<action>' ) {
                &do( $bag{chl} => $line{tidbit} );
            } else {
                if ( lc $bag{msg} eq 'bucket' and lc $line{verb} eq 'is' ) {
                    $bag{orig}   = 'I';
                    $line{verb} = 'am';
                }
                &say( $bag{chl} => "$bag{msg} $line{verb} $line{tidbit}" );
            }
            return;
        } elsif ( $bag{msg} =~ s/^what is |^what's |^the //i ) {
            &lookup(%bag);
            return;
        }

        if (
                $bag{editable}
            and $bag{addressed}
            and (  $bag{orig} =~ /(.*?) (?:is ?|are ?)(<\w+>)\s*(.*)()/i
                or $bag{orig} =~ /(.*?)\s+(<\w+(?:'t)?>)\s*(.*)()/i
                or $bag{orig} =~ /(.*?)(<'s>)\s+(.*)()/i
                or $bag{orig} =~ /(.*?)\s+(is(?: also)?|are)\s+(.*)/i )
          )
        {
            my ( $fact, $verb, $tidbit, $forced ) = ( $1, $2, $3, defined $4 );

            if ( not $bag{addressed} and $fact =~ /^[^a-zA-Z]*<.?\S+>/ ) {
                Log "Not learning from what seems to be an IRC quote: $fact";

                # don't learn from IRC quotes
                return;
            }

            if ( $tidbit =~ /=~/ and not $forced ) {
                Log "Not learning what looks like a botched =~ query";
                &say( $bag{chl} => "$bag{who}: Fix your =~ command." );
                return;
            }

            if ( $fact eq 'you' and $verb eq 'are' ) {
                $fact = $nick;
                $verb = "is";
            } elsif ( $fact eq 'I' and $verb eq 'am' ) {
                $fact = $bag{who};
                $verb = "is";
            }

            $stats{learn}++;
            my $also = 0;
            if ( $tidbit =~ s/^<(action|reply)>\s*// ) {
                $verb = "<$1>";
            } elsif ( $verb eq 'is also' ) {
                $also = 1;
                $verb = 'is';
            } elsif ($forced) {
                $bag{forced} = 1;
                if ( $verb ne '<action>' and $verb ne '<reply>' ) {
                    $verb =~ s/^<|>$//g;
                }

                if ( $fact =~ s/ is also$// ) {
                    $also = 1;
                } else {
                    $fact =~ s/ is$//;
                }
            }
            $fact = &trim($fact);

            if (    &config("your_mom_is")
                and not $bag{op}
                and $verb eq 'is'
                and rand(100) < &config("your_mom_is") )
            {
                $tidbit =~ s/\W+$//;
                &say( $bag{chl} => "$bag{who}: Your mom is $tidbit!" );
                return;
            }

            if ( lc $fact eq lc $bag{who} or lc $fact eq lc "$bag{who} quotes" )
            {
                Log "Not allowing $bag{who} to edit his own factoid";
                &say( $bag{chl} =>
                      "Please don't edit your own factoids, $bag{who}." );
                return;
            }

            $fact = &decommify($fact);
            Log "Learning '$fact' '$verb' '$tidbit'";
            &sql(
                'select id, tidbit from bucket_facts
                  where fact = ? and verb = "<alias>"',
                [$fact],
                {
                    %bag,
                    fact    => $fact,
                    verb    => $verb,
                    tidbit  => $tidbit,
                    cmd     => "unalias",
                    db_type => "SINGLE",
                }
            );

            return;
        } elsif (
            $bag{orig} =~ m{ ^ \s* (how|what|whom?|where|why) # interrogative
                                   \s+ does
                                   \s+ (\S+) # nick
                                   \s+ (\w+) # verb
                                   (?:.*) # more 
                                 }xi
          )
        {
            my ( $inter, $member, $verb, $more ) = ( $1, $2, $3, $4 );
            if ( &DEBUG or $irc->is_channel_member( $bag{chl}, $member ) ) {
                Log "Looking up $member($verb) + $more";
                &lookup(
                    %bag,
                    editable => 0,
                    msg      => $member,
                    orig     => $member,
                    verb     => &s_form($verb),
                    starts   => $more,
                );

                return;
            }
        } elsif ( $bag{addressed}
            and $bag{orig} =~ m{[+\-*%/]}
            and $bag{orig} =~ m{^([\s0-9a-fA-F_x+\-*%/.()]+)$} )
        {

            # Mathing!
            $stats{math}++;
            my $res;
            my $exp = $1;

         # if there's hex in here, but not prefixed with 0x, just throw an error
            foreach my $num ( $exp =~ /([x0-9a-fA-F.]+)/g ) {
                next if $num =~ /^0x|^[0-9.]+$|^[0-9.]+[eE][0-9]+$/;
                &error( $bag{chl}, $bag{who} );
                return;
            }

            if ( $exp !~ /\*\*/ and $math ) {
                my $newexp;
                foreach my $word ( split /( |-[\d_e.]+|\*\*|[+\/%()*])/, $exp )
                {
                    $word = "new $math(\"$word\")" if $word =~ /^[_0-9.e]+$/;
                    $newexp .= $word;
                }
                $exp = $newexp;
            }
            $exp = "package Bucket::Eval; \$res = 0 + $exp;";
            Log " -> $exp";
            eval $exp;
            Log "-> $res";
            if ( defined $res ) {
                if ( length $res < 400 ) {
                    &say( $bag{chl} => "$bag{who}: $res" );
                } else {
                    $res->accuracy(400);
                    &say(   $bag{chl} => "$bag{who}: "
                          . $res->mantissa() . "e"
                          . $res->exponent() );
                }
            } elsif ($@) {
                $@ =~ s/ at \(.*//;
                &say( $bag{chl} => "Sorry, $bag{who}, there was an error: $@" );
            } else {
                &error( $bag{chl}, $bag{who} );
            }
            return;
        } elsif ( $bag{addressed} ) {
            &error( $bag{chl}, $bag{who} );
            return;
        }

        #Log "extra work on $bag{msg}";
        if ( $bag{orig} =~ /^say (.*)/i ) {
            my $msg = $1;
            $stats{say}++;
            $msg =~ s/\W+$//;
            $msg .= "!";
            &say( $bag{chl} => ucfirst $msg );
        } elsif ( $bag{orig} =~ /^(?:Do you|Does anyone) know (\w+)/i
            and $1 !~ /who|of|if|why|where|what|when|whose|how/i )
        {
            $stats{hum}++;
            &say( $bag{chl} => "No, but if you hum a few bars I can fake it" );
        } elsif ( &config("max_sub_length")
            and length( $bag{orig} ) < &config("max_sub_length")
            and $bag{orig} =~ s/(\w+)-ass (\w+)/$1 ass-$2/ )
        {
            $stats{ass}++;
            &say( $bag{chl} => $bag{orig} );
        } elsif ( &config("max_sub_length")
            and length( $bag{orig} ) < &config("max_sub_length")
            and rand(100) < &config("the_fucking")
            and $bag{orig} =~ s/\bthe fucking\b/fucking the/ )
        {
            $stats{fucking}++;
            &say( $bag{chl} => $bag{orig} );
        } elsif (
            &config("max_sub_length")
            and length( $bag{orig} ) < &config("max_sub_length")
            and $bag{orig} !~ /extra|except/
            and rand(100) < &config("ex_to_sex")
            and (  $bag{orig} =~ s/\ban ex/a sex/
                or $bag{orig} =~ s/\bex/sex/ )
          )
        {
            $stats{sex}++;
            if ( $bag{type} eq 'irc_ctcp_action' ) {
                &do( $bag{chl} => $bag{orig} );
            } else {
                &say( $bag{chl} => $bag{orig} );
            }
        } elsif (
            $bag{orig} !~ /\?\s*$/
            and $bag{editable}
            and $bag{orig} =~ /^(?:
                               puts \s (\S.+) \s in \s (the \s)? $nick\b
                             | (?:gives|hands) \s $nick \s (\S.+)
                             | (?:gives|hands) \s (\S.+) \s to $nick\b
                            )/ix
            or (
                    $bag{addressed}
                and $bag{orig} =~ /^(?:
                                 take \s this \s (\S.+)
                               | have \s (an? \s \S.+)
                              )/x
            )
          )
        {
            my $item = ( $1 || $2 || $3 );
            $item =~ s/\b(?:his|her|their)\b/$bag{who}\'s/;
            $item =~ s/[ .?!]+$//;
            $item =~ s/\$+([a-zA-Z])/$1/g;

            my ( $rc, @dropped ) = &put_item( $item, 0 );
            if ( $rc == 1 ) {
                &cached_reply( $bag{chl}, $bag{who}, $item, "takes item" );
            } elsif ( $rc == 2 ) {
                &cached_reply( $bag{chl}, $bag{who}, [ $item, @dropped ],
                    "pickup full" );
            } elsif ( $rc == -1 ) {
                &cached_reply( $bag{chl}, $bag{who}, $item, "duplicate item" );
                return;
            } else {
                Log "&put_item($item) returned weird value: $rc";
                return;
            }

            Log "Taking $item from $bag{who}: " . join ", ", @inventory;
            &sql(
                'insert ignore into bucket_items (what, user, channel)
                         values (?, ?, ?)',
                [ $item, $bag{who}, $bag{chl} ]
            );
            &random_item_cache( $_[KERNEL] );
        } else {    # lookup band name!
            if (    &config("band_name")
                and $bag{type} eq 'irc_public'
                and rand(100) < &config("band_name")
                and $bag{orig} !~ m{https?://}i )
            {
                my $name = $bag{orig};
                my $nicks = join "|", map { "\Q$_" } $irc->nicks();
                $nicks = qr/(?:^|\b)(?:$nicks)(?:\b|$)/i;
                $name =~ s/^$nicks://;
                unless ( $name =~ s/$nicks//g ) {
                    $name =~ s/[^\- \w']+//g;
                    $name =~ s/^\s+|\s+$//g;
                    $name =~ s/\s\s+/ /g;
                    my $stripped_name = $name;
                    $stripped_name =~ s/'//g;
                    my @words = split( ' ', $stripped_name );
                    if (    length $name <= 32
                        and @words == 3
                        and $name !~ /\b[ha]{2,}\b/i )
                    {
                        &sql(
                            'select value
                              from bucket_values left join bucket_vars
                                   on bucket_vars.id = bucket_values.var_id
                              where name = "band" and value = ?
                              limit 1',
                            [$stripped_name],
                            {
                                %bag,
                                name          => $name,
                                stripped_name => $stripped_name,
                                words         => \@words,
                                cmd           => "band_name",
                                db_type       => 'SINGLE',
                            }
                        );
                    }
                }
            }
        }
    } elsif ( $bag{cmd} eq 'create_var' ) {
        if ( $res->{INSERTID} ) {
            $replacables{$bag{var}}{id} = $res->{INSERTID};
            Log "ID for $bag{var}: $res->{INSERTID}";
        } else {
            Log "ERR: create_var called without an INSERTID!";
        }
    } elsif ( $bag{cmd} eq 'load_gender' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        $stats{users}{genders}{lc $bag{nick}} =
          lc( $line{gender} || "androgynous" );
    } elsif ( $bag{cmd} eq 'load_vars' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : [];
        my ( @small, @large );
        foreach my $line (@lines) {
            if ( $line->{num} > &config("value_cache_limit") ) {
                push @large, $line->{name};
            } else {
                push @small, $line->{name};
            }
        }
        Log "Small vars: @small";
        Log "Large vars: @large";

        if (@small) {

            # load the smaller variables
            &sql(
                'select vars.id id, name, perms, type, value
                  from bucket_vars vars
                       left join bucket_values vals
                       on vars.id = vals.var_id
                  where name in (' . join( ",", map { "?" } @small ) . ')
                  order by vars.id',
                \@small,
                {cmd => "load_vars_cache", db_type => 'MULTIPLE'},
            );
        }

        # make note of the larger variables, and preload a cache
        foreach my $var (@large) {
            &sql(
                'select vars.id id, name, perms, type, value
                  from bucket_vars vars
                       left join bucket_values vals
                       on vars.id = vals.var_id
                  where name = ?
                  order by rand()
                  limit 10',
                [$var],
                {cmd => "load_vars_large", db_type => 'MULTIPLE'}
            );
        }
    } elsif ( $bag{cmd} eq 'load_vars_large' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : [];

        Log "Loading large replacables: $lines[0]{name}";
        foreach my $line (@lines) {
            unless ( exists $replacables{$line->{name}} ) {
                $replacables{$line->{name}} = {
                    cache => [],
                    perms => $line->{perms},
                    id    => $line->{id},
                    type  => $line->{type}
                };
            }

            push @{$replacables{$line->{name}}{cache}}, $line->{value};
        }
    } elsif ( $bag{cmd} eq 'load_vars_cache' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : [];

        Log "Loading small replacables";
        foreach my $line (@lines) {
            unless ( exists $replacables{$line->{name}} ) {
                $replacables{$line->{name}} = {
                    vals  => [],
                    perms => $line->{perms},
                    id    => $line->{id},
                    type  => $line->{type}
                };
            }

            push @{$replacables{$line->{name}}{vals}}, $line->{value};
        }

        Log "Loaded vars:",
          &make_list(
            map { "$_ (" . scalar @{$replacables{$_}{vals}} . ")" }
            sort keys %replacables
          );
    } elsif ( $bag{cmd} eq 'dump_var' ) {
        unless ( ref $res->{RESULT} ) {
            &say( $bag{chl} => "Sorry, $bag{who}, something went wrong!" );
            return;
        }

        my $url = &config("www_url") . "/" . uri_escape("var_$bag{name}.txt");
        if ( open( DUMP, ">", &config("www_root") . "/var_$bag{name}.txt" ) ) {
            my $count = 0;
            foreach ( @{$res->{RESULT}} ) {
                print DUMP "$_->{value}\n";
                $count++;
            }
            close DUMP;
            &say( $bag{chl} =>
                  "$bag{who}: Here's the full list ( $count ): $url" );
        } else {
            &say( $bag{chl} =>
                  "Sorry, $bag{who}, failed to dump out $bag{name}: $!" );
        }
    } elsif ( $bag{cmd} eq 'band_name' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        unless ( $line{value} ) {
            &check_band_name( \%bag );
        }
    } elsif ( $bag{cmd} eq 'edit' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : [];

        unless (@lines) {
            &error( $bag{chl}, $bag{who} );
            return;
        }

        if ( $lines[0]->{protected} and not $bag{op} ) {
            Log "$bag{who}: that factoid is protected";
            &say( $bag{chl} => "Sorry, $bag{who}, that factoid is protected" );
            return;
        }

        my ( $gflag, $iflag );
        $gflag = ( $bag{op} and $bag{flag} =~ s/g//g );
        $iflag = ( $bag{flag} =~ s/i//g ? "i" : "" );
        my $count = 0;
        $undo{$bag{chl}} = [
            'edit', $bag{who},
            [],     "$lines[0]->{fact} =~ s/$bag{old}/$bag{new}/"
        ];

        foreach my $line (@lines) {
            my $fact = "$line->{verb} $line->{tidbit}";
            $fact = "$line->{verb} $line->{tidbit}" if $line->{verb} =~ /<.*>/;
            if ($gflag) {
                my $c;
                next unless $c = $fact =~ s/(?$iflag:\Q$bag{old}\E)/$bag{new}/g;
                $count += $c;
            } else {
                next unless $fact =~ s/(?$iflag:\Q$bag{old}\E)/$bag{new}/;
            }

            if ( $fact =~ /\S/ ) {
                my ( $verb, $tidbit );
                if ( $fact =~ /^<(\w+)>\s*(.*)/ ) {
                    ( $verb, $tidbit ) = ( "<$1>", $2 );
                } else {
                    ( $verb, $tidbit ) = split ' ', $fact, 2;
                }

                unless (
                    &validate_factoid(
                        {
                            %bag,
                            fact   => $fact,
                            verb   => $verb,
                            tidbit => $tidbit
                        }
                    )
                  )
                {
                    next;
                }

                $stats{edited}++;
                Report "$bag{who} edited $line->{fact}(#$line->{id})"
                  . " in $bag{chl}: New values: $fact";
                Log "$bag{who} edited $line->{fact}($line->{id}): "
                  . "New values: $fact";

                &sql(
                    'update bucket_facts set verb=?, tidbit=?
                       where id=? limit 1',
                    [ $verb, $tidbit, $line->{id} ],
                );
                push @{$undo{$bag{chl}}[2]},
                  [ 'update', $line->{id}, $line->{verb}, $line->{tidbit} ];
            } elsif ( $bag{op} ) {
                $stats{deleted}++;
                Report "$bag{who} deleted $line->{fact}($line->{id})"
                  . " in $bag{chl}: $line->{verb} $line->{tidbit}";
                Log "$bag{who} deleted $line->{fact}($line->{id}):"
                  . " $line->{verb} $line->{tidbit}";
                &sql(
                    'delete from bucket_facts where id=? limit 1',
                    [ $line->{id} ],
                );
                push @{$undo{$bag{chl}}[2]}, [ 'insert', {%$line} ];
            } else {
                &error( $bag{chl}, $bag{who} );
                Log "$bag{who}: $line->{fact} =~ s/// failed";
            }

            if ($gflag) {
                next;
            }
            &say( $bag{chl} => "Okay, $bag{who}, factoid updated." );

            if ( exists $fcache{lc $line->{fact}} ) {
                Log "Updating cache for '$line->{fact}'";
                &cache( $_[KERNEL], $line->{fact} );
            }
            return;
        }

        if ($gflag) {
            if ( $count == 1 ) {
                $count = "one match";
            } else {
                $count .= " matches";
            }
            &say( $bag{chl} => "Okay, $bag{who}; $count." );

            if ( exists $fcache{lc $bag{fact}} ) {
                Log "Updating cache for '$bag{fact}'";
                &cache( $_[KERNEL], $bag{fact} );
            }
            return;
        }

        &error( $bag{chl}, $bag{who} );
        Log "$bag{who}: $bag{fact} =~ s/// failed";
    } elsif ( $bag{cmd} eq 'forget' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        unless ( keys %line ) {
            &error( $bag{chl}, $bag{who} );
            Log "Nothing to forget in '$bag{id}'";
            return;
        }

        $undo{$bag{chl}} = [ 'insert', $bag{who}, \%line ];
        Report "$bag{who} called forget to delete "
          . "'$line{fact}', '$line{verb}', '$line{tidbit}'";
        Log "forgetting $bag{fact}";
        &sql( 'delete from bucket_facts where id=?', [ $line{id} ], );
        &say(
            $bag{chl} => "Okay, $bag{who}, forgot that",
            "$line{fact} $line{verb} $line{tidbit}"
        );
    } elsif ( $bag{cmd} eq 'delete_id' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        unless ( $line{fact} ) {
            &error( $bag{chl}, $bag{who} );
            Log "Nothing found in id $bag{fact}";
            return;
        }

        $undo{$bag{chl}} = [ 'insert', $bag{who}, \%line, $bag{fact} ];
        Report "$bag{who} deleted '$line{fact}' (#$bag{fact}) in $bag{chl}";
        Log "deleting $bag{fact}";
        &sql( 'delete from bucket_facts where id=?', [ $bag{fact} ], );
        &say( $bag{chl} => "Okay, $bag{who}, deleted "
              . "'$line{fact} $line{verb} $line{tidbit}'." );
    } elsif ( $bag{cmd} eq 'delete' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : ();
        unless (@lines) {
            &error( $bag{chl}, $bag{who} );
            Log "Nothing to delete in '$bag{fact}'";
            return;
        }

        $undo{$bag{chl}} = [ 'insert', $bag{who}, \@lines, $bag{fact} ];
        Report "$bag{who} deleted '$bag{fact}' in $bag{chl}";
        Log "deleting $bag{fact}";
        &sql( 'delete from bucket_facts where fact=?', [ $bag{fact} ], );
        my $s = "";
        $s = "s" unless @lines == 1;
        &say(   $bag{chl} => "Okay, $bag{who}, "
              . scalar @lines
              . " factoid$s deleted." );
    } elsif ( $bag{cmd} eq 'unalias' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        my $fact = $bag{fact};
        if ( $line{id} ) {
            Log "Dealiased $fact => $line{tidbit}";
            $fact = $line{tidbit};
        }

        &sql(
            'select id from bucket_facts where fact = ? and tidbit = ?',
            [ $fact, $bag{tidbit} ],
            {%bag, fact => $fact, cmd => "learn1", db_type => 'SINGLE',}
        );
    } elsif ( $bag{cmd} eq 'learn1' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        if ( $line{id} ) {
            &say( $bag{chl} => "$bag{who}: I already had it that way" );
            return;
        }

        &sql(
            'select protected from bucket_facts where fact = ?',
            [ $bag{fact} ],
            {%bag, cmd => "learn2", db_type => 'SINGLE',}
        );
    } elsif ( $bag{cmd} eq 'learn2' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        if ( $line{protected} ) {
            if ( $bag{op} ) {
                unless ( $bag{forced} ) {
                    Log "$bag{who}: that factoid is protected (op, not forced)";
                    &say( $bag{chl} =>
                            "Sorry, $bag{who}, that factoid is protected.  "
                          . "Use <$bag{verb}> to override." );
                    return;
                }

                Log "$bag{who}: overriding protection.";
            } else {
                Log "$bag{who}: that factoid is protected";
                &say( $bag{chl} =>
                      "Sorry, $bag{who}, that factoid is protected" );
                return;
            }
        }

        unless ( &validate_factoid( \%bag ) ) {
            &say( $bag{chl} => "Sorry, $bag{who}, I can't do that." );
            return;
        }

        if ( lc $bag{verb} eq '<alias>' ) {
            &say( $bag{chl} => "$bag{who}, please use the 'alias' command." );
            return;
        }

        # we said 'is also' but we didn't get any existing results
        if ( $bag{also} and $res->{RESULT} ) {
            delete $bag{also};
        }

        &sql(
            'insert bucket_facts (fact, verb, tidbit, protected)
                     values (?, ?, ?, ?)',
            [ $bag{fact}, $bag{verb}, $bag{tidbit}, $line{protected} || 0 ],
            {%bag, cmd => "learn3"}
        );
    } elsif ( $bag{cmd} eq 'learn3' ) {
        if ( $res->{INSERTID} ) {
            $undo{$bag{chl}} = [
                'delete',         $bag{who},
                $res->{INSERTID}, "that '$bag{fact}' is '$bag{tidbit}'"
            ];

            $stats{last_fact}{$bag{chl}} = $res->{INSERTID};

            Report "$bag{who} taught in $bag{chl} (#$res->{INSERTID}):"
              . " '$bag{fact}', '$bag{verb}', '$bag{tidbit}'";
            Log "$bag{who} taught '$bag{fact}', '$bag{verb}', '$bag{tidbit}'";
        }
        my $ack;
        if ( $bag{also} ) {
            $ack = "Okay, $bag{who} (added as only factoid).";
        } else {
            $ack = "Okay, $bag{who}.";
        }

        if ( $bag{ack} ) {
            $ack = $bag{ack};
        }
        &say( $bag{chl} => $ack );

        if ( exists $fcache{lc $bag{fact}} ) {
            Log "Updating cache for '$bag{fact}'";
            &cache( $_[KERNEL], $bag{fact} );
        }
    } elsif ( $bag{cmd} eq 'merge' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        Report "$bag{who} merged in $bag{chl} '$bag{src}' with '$bag{dst}'";
        Log "$bag{who} merged '$bag{src}' with '$bag{dst}'";
        if ( $line{id} and $line{verb} eq '<alias>' ) {
            &say( $bag{chl} => "Sorry, $bag{who}, those are already merged." );
            return;
        }

        if ( $line{id} ) {
            &sql( 'update ignore bucket_facts set fact=? where fact=?',
                [ $bag{dst}, $bag{src} ] );
            &sql( 'delete from bucket_facts where fact=?', [ $bag{src} ] );
        }

        &sql(
            'insert bucket_facts (fact, verb, tidbit, protected)
                     values (?, "<alias>", ?, 1)',
            [ $bag{src}, $bag{dst} ],
        );

        &say( $bag{chl} => "Okay, $bag{who}." );
        $undo{$bag{chl}} = ['merge'];
    } elsif ( $bag{cmd} eq 'alias1' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();
        if ( $line{id} and $line{verb} ne '<alias>' ) {
            &say( $bag{chl} => "Sorry, $bag{who}, "
                  . "there is already a factoid for '$bag{src}'." );
            return;
        }

        Report "$bag{who} aliased in $bag{chl} '$bag{src}' to '$bag{dst}'";
        Log "$bag{who} aliased '$bag{src}' to '$bag{dst}'";
        &sql(
            'insert bucket_facts (fact, verb, tidbit, protected)
                     values (?, "<alias>", ?, 1)',
            [ $bag{src}, $bag{dst} ],
            {%bag, fact => $bag{src}, tidbit => $bag{dst}, cmd => "learn3"}
        );
    } elsif ( $bag{cmd} eq 'cache' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : [];
        $fcache{lc $bag{key}} = [];
        foreach my $line (@lines) {
            $fcache{lc $bag{key}} = [@lines];
        }
        Log "Cached " . scalar(@lines) . " factoids for $bag{key}";
    } elsif ( $bag{cmd} eq 'report' ) {
        my %line = ref $res->{RESULT} ? %{$res->{RESULT}} : ();

        if ( $line{id} ) {
            if ( keys %{$stats{last_vars}{$bag{chl}}} ) {
                my $report = Dumper( $stats{last_vars}{$bag{chl}} );
                $report =~ s/\n//g;
                $report =~ s/\$VAR1 = //;
                $report =~ s/  +/ /g;
                &say(   $bag{chl} => "$bag{who}: That was "
                      . ( $stats{last_alias_chain}{$bag{chl}} || "" )
                      . "'$line{fact}' "
                      . "(#$bag{id}): $line{verb} $line{tidbit};  "
                      . "vars used: $report." );
            } else {
                &say(   $bag{chl} => "$bag{who}: That was "
                      . ( $stats{last_alias_chain}{$bag{chl}} || "" )
                      . "'$line{fact}' "
                      . "(#$bag{id}): $line{verb} $line{tidbit}" );
            }
        } else {
            &say( $bag{chl} => "$bag{who}: No idea!" );
        }
    } elsif ( $bag{cmd} eq 'literal' ) {
        my @lines = ref $res->{RESULT} ? @{$res->{RESULT}} : [];

        unless (@lines) {
            if ( $bag{addressed} ) {
                &error( $bag{chl}, $bag{who}, "$bag{who}: " );
            }
            return;
        }

        if ( $bag{page} ne "*" and $bag{page} > 10 ) {
            $bag{page} = "*";
        }

        if ( $lines[0]->{verb} eq "<alias>" ) {
            my $new_fact = $lines[0]->{tidbit};
            &sql(
                'select id, verb, tidbit, mood, chance, protected from
                  bucket_facts where fact = ? order by id',
                [$new_fact],
                {
                    %bag,
                    cmd      => "literal",
                    alias_to => $new_fact,
                    db_type  => 'MULTIPLE',
                }
            );
            Report "Asked for the 'literal' of an alias,"
              . " being smart and redirecting to '$new_fact'";
            return;
        }

        if (    $bag{page} eq '*'
            and &config("www_url")
            and &config("www_root")
            and -w &config("www_root") )
        {
            my $url =
              &config("www_url") . "/" . uri_escape("literal_$bag{fact}.txt");
            Report
              "$bag{who} asked in $bag{chl} to dump out $bag{fact} -> $url";
            if (
                open( DUMP, ">", &config("www_root") . "/literal_$bag{fact}.txt"
                )
              )
            {
                if ( defined $bag{alias_to} ) {
                    print DUMP "Alias to $bag{alias_to}\n";
                }
                my $count = @lines;
                while ( my $fact = shift @lines ) {
                    if ( $bag{op} ) {
                        print DUMP "#$fact->{id}\t";
                    }

                    print DUMP join "\t", $fact->{verb}, $fact->{tidbit};
                    print DUMP "\n";
                }
                close DUMP;
                &say( $bag{chl} =>
                      "$bag{who}: Here's the full list ($count): $url" );
                return;
            } else {
                Log "Failed to write dump file: $!";
                &error( $bag{chl}, $bag{who} );
                return;
            }
        }

        $bag{page} = 1 if $bag{page} eq '*';

        my $prefix = "$bag{fact}";
        if ( $lines[0]->{protected} and not defined $bag{alias_to} ) {
            $prefix .= " (protected)";
        } elsif ( defined $bag{alias_to} ) {
            $prefix .= " (=> $bag{alias_to})";
        }

        my $answer;
        my $linelen = 400;
        while ( $bag{page}-- ) {
            $answer = "";
            while ( my $fact = shift @lines ) {
                my $bit;
                if ( $bag{op} ) {
                    $bit = "(#$fact->{id}) ";
                }
                $bit .= "$fact->{verb} $fact->{tidbit}";
                $bit =~ s/\|/\\|/g;
                if ( length("$prefix $answer|$bit") > $linelen and $answer ) {
                    unshift @lines, $fact;
                    last;
                }
                if ( $fact->{chance} ) {
                    $bit .= "[$fact->{chance}%]";
                }
                if ( $fact->{mood} ) {
                    my @moods = ( ":<", ":(", ":|", ":)", ":D" );
                    $bit .= "{$moods[$fact->{mood}/20]}";
                }

                $answer = join "|", ( $answer ? $answer : () ), $bit;
            }
        }

        if (@lines) {
            $answer .= "|" . @lines . " more";
        }
        &say( $bag{chl} => "$prefix $answer" );
    } elsif ( $bag{cmd} eq 'stats1' ) {
        $stats{triggers} = $res->{RESULT}{c};
    } elsif ( $bag{cmd} eq 'stats2' ) {
        $stats{rows} = $res->{RESULT}{c};
    } elsif ( $bag{cmd} eq 'stats3' ) {
        $stats{items}        = $res->{RESULT}{c};
        $stats{stats_cached} = time;
    } elsif ( $bag{cmd} eq 'itemcache' ) {
        @random_items =
          ref $res->{RESULT} ? map { $_->{what} } @{$res->{RESULT}} : [];
        Log "Updated random item cache: ", join ", ", @random_items;

        if ( $stats{preloaded_items} ) {
            if ( @random_items > $stats{preloaded_items} ) {
                @inventory =
                  splice( @random_items, 0, $stats{preloaded_items}, () );
            } else {
                @inventory    = @random_items;
                @random_items = ();
            }
            delete $stats{preloaded_items};

            &random_item_cache( $_[KERNEL] );
        }
    } elsif ( $bag{cmd} eq 'tla' ) {
        if ( $res->{RESULT}{value} ) {
            $stats{lookup_tla}++;
            $bag{tla} =~ s/\W//g;
            $stats{last_fact}{$bag{chl}} = "a possible meaning of $bag{tla}.";
            &say(
                $bag{chl} => "$bag{who}: " . join " ",
                map { ucfirst }
                  split ' ', $res->{RESULT}{value}
            );
        }
    }
}

