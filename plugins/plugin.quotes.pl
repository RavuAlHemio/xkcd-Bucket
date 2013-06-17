# BUCKET PLUGIN

use BucketBase qw/say Log Report config save post/;

my %history;

sub signals {
    return (qw/on_public say do/);
}

sub commands {
    return (
        {
            label     => 'do quote',
            addressed => 1,
            operator  => 1,
            editable  => 0,
            re        => qr/^do quote ([\w\-]+)\W*$/i,
            callback  => \&allow_quote
        },
        {
            label     => 'dont quote',
            addressed => 1,
            operator  => 1,
            editable  => 0,
            re        => qr/^don't quote ([\w\-]+)\W*$/i,
            callback  => \&disallow_quote
        },
        {
            label     => 'allow quotes from',
            addressed => 1,
            operator  => 1,
            editable  => 0,
            re        => qr/^allow quotes from ([\w\-]+)\W*$/i,
            callback  => \&allow_author
        },
        {
            label     => 'forbid quotes from',
            addressed => 1,
            operator  => 1,
            editable  => 0,
            re        => qr/^forbid quotes from ([\w\-]+)\W*$/i,
            callback  => \&disallow_author
        },
        {
            label     => 'allow quotes attributed to',
            addressed => 1,
            operator  => 1,
            editable  => 0,
            re        => qr/^allow quotes attributed to ([\w\-]+)\W*$/i,
            callback  => \&allow_attributee
        },
        {
            label     => 'forbid quotes attributed to',
            addressed => 1,
            operator  => 1,
            editable  => 0,
            re        => qr/^forbid quotes attributed to ([\w\-]+)\W*$/i,
            callback  => \&disallow_attributee
        },
        {
            label     => 'remember',
            addressed => 1,
            operator  => 0,
            editable  => 0,
            re        => qr/^remember (\S+) ([^<>]+)$/i,
            callback  => \&quote
        },
        {
            label     => 'misattribute',
            addressed => 1,
            operator  => 0,
            editable  => 0,
            re        => qr/^misattribute (\S+) ([^<>]+) to (\S+)$/i,
            callback  => \&misattribute
        },
    );
}

sub settings {
    return ( history_size => [ i => 30 ], );
}

sub route {
    my ( $package, $sig, $data ) = @_;

    if ( $sig eq 'on_public' ) {
        &save_history($data);
    } elsif ( $sig eq 'say' or $sig eq 'do' ) {
        &save_self_history( $data, $sig );
    }

    return 0;
}

sub save_history {
    my $bag = shift;

    $history{ $bag->{chl} } = [] unless ( exists $history{ $bag->{chl} } );
    push @{ $history{ $bag->{chl} } },
      [ $bag->{who}, $bag->{type}, $bag->{msg} ];

    while ( @{ $history{ $bag->{chl} } } > &config("history_size") ) {
        last unless shift @{ $history{ $bag->{chl} } };
    }
}

sub save_self_history {
    my ( $bag, $type ) = @_;
    push @{ $history{ $bag->{chl} } },
      [
        &config("nick"), ( $type eq 'say' ? 'irc_public' : 'irc_ctcp_action' ),
        $bag->{text}
      ];
}

sub allow_quote {
    my $bag = shift;
    &make_quotable( $1, 1, $bag, "protected_quotes" );
}

sub disallow_quote {
    my $bag = shift;
    &make_quotable( $1, 0, $bag, "protected_quotes" );
}

sub allow_attributee {
    my $bag = shift;
    &make_quotable( $1, 1, $bag, "protected_quote_attributees" );
}

sub disallow_attributee {
    my $bag = shift;
    &make_quotable( $1, 0, $bag, "protected_quote_attributees" );
}

sub allow_author {
    my $bag = shift;
    &make_quotable( $1, 1, $bag, "protected_quote_authors" );
}

sub disallow_author {
    my $bag = shift;
    &make_quotable( $1, 0, $bag, "protected_quote_authors" );
}

sub make_quotable {
    my ( $target, $bit, $bag, $confvar ) = @_;

    my $quoteable = &config($confvar) || {};
    if ($bit) {
        delete $quoteable->{ lc $target };
    } else {
        $quoteable->{ lc $target } = 1;
    }
    &config( $confvar, $quoteable );
    &say( $bag->{chl} => "Okay, $bag->{who}." );
    &Report(
        "$bag->{who} asked to",
        ( $bit ? "allow full" : "restrict" ),
        "access to the '$target quotes' factoid."
    );
    &save;
}

sub attribute_quote {
    my ( $bag, $author, $re, $attributee ) = @_;

    if (    &config("protected_quote_authors")
        and &config("protected_quote_authors")->{ lc $author } )
    {
        &say( $bag->{chl} =>
              "Sorry, $bag->{who}, I mustn't remember quotes by $author."
        );
        return;
    }

    if (    &config("protected_quote_attributees")
        and &config("protected_quote_attributees")->{ lc $attributee } )
    {
        &say( $bag->{chl} =>
              "Sorry, $bag->{who}, I mustn't remember quotes attributed to $attributee."
        );
        return;
    }

    if ( lc $author eq lc $bag->{who} ) {
        &say( $bag->{chl} => "$bag->{who}, please don't quote yourself." );
        return;
    }

    my $match;
    foreach my $line ( reverse @{ $history{ $bag->{chl} } } ) {
        next unless lc $line->[0] eq lc $author;
        next unless $line->[2] =~ /\Q$re/i;

        $match = $line;
        last;
    }

    unless ($match) {
        &say( $bag->{chl} =>
"Sorry, $bag->{who}, I don't remember what $author said about '$re'."
        );
        return;
    }

    my $quote;
    $match->[2] =~ s/^(?:\S+:)? +//;
    if ( $match->[1] eq 'irc_ctcp_action' ) {
        $quote = "* $attributee $match->[2]";
    } else {
        $quote = "<$attributee> $match->[2]";
    }
    $quote =~ s/\$/\\\$/g;
    &Log("Remembering '$attributee quotes' '<reply>' '$quote'");
    &post(
        db  => 'SINGLE',
        SQL => 'select id, tidbit from bucket_facts 
                where fact = ? and verb = \'<alias>\'',
        PLACEHOLDERS => ["$attributee quotes"],
        BAGGAGE      => {
            %$bag,
            msg       => "$attributee quotes <reply> $quote",
            orig      => "$attributee quotes <reply> $quote",
            addressed => 1,
            fact      => "$attributee quotes",
            verb      => "<reply>",
            tidbit    => $quote,
            cmd       => "unalias",
            ack       => "Okay, $bag->{who}, remembering \"$match->[2]\".",
        },
        EVENT => 'db_success'
    );
}

sub quote {
    my $bag = shift;
    my ( $target, $re ) = ( $1, $2 );

    if (    &config("protected_quotes")
        and &config("protected_quotes")->{ lc $target } )
    {
        &say( $bag->{chl} =>
              "Sorry, $bag->{who}, you can't use remember for $target quotes."
        );
        return;
    }

    &attribute_quote( $bag, $target, $re, $target );
}

sub misattribute {
    my $bag = shift;
    my ( $author, $re, $attributee ) = ( $1, $2, $3 );

    &attribute_quote( $bag, $author, $re, $attributee );
}
