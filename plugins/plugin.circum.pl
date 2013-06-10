# BUCKET PLUGIN

use BucketBase qw/say config/;

sub signals {
    return (qw/on_public/);
}

sub route {
    my ( $package, $sig, $data ) = @_;

    # anything that comes here should be processed the same way
    &sub_circum($data);

    return 0;
}

sub sub_circum {
    my ($data) = @_;

    if ( &config("max_sub_length")
        and length( $data->{msg} ) < &config("max_sub_length")
        and $data->{msg} =~ /circum/ )
    {
        my $circumvented = $data->{msg};
        my $circumcised = $circumvented;

        $circumcised =~ s/\bcircumvention\b/circumcision/;
        $circumcised =~ s/\bcircumvent\b/circumcise/;
        $circumcised =~ s/\bcircumvented\b/circumcised/;

        if ( $circumvented !~ $circumcised ) {
            &say( $data->{chl} => $circumcised );
        }
    }
}

