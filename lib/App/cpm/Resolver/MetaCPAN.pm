package App::cpm::Resolver::MetaCPAN;
use strict;
use warnings;
use JSON::PP ();
use App::cpm::HTTP;
our $VERSION = '0.967';

sub new {
    my ($class, %option) = @_;
    my $uri = $option{uri} || "https://fastapi.metacpan.org/v1/download_url/";
    $uri =~ s{/*$}{/};
    bless { %option, uri => $uri, http => App::cpm::HTTP->new }, $class;
}

sub _encode {
    my $str = shift;
    $str =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;
    $str;
}

sub resolve {
    my ($self, $job) = @_;
    if ($self->{only_dev} and !$job->{dev}) {
        return { error => "skip, because MetaCPAN is configured to resolve dev releases only" };
    }

    my %query = (
        ( ($self->{dev} || $job->{dev}) ? (dev => 1) : () ),
        ( $job->{version_range} ? (version => $job->{version_range}) : () ),
    );
    my $query = join "&", map { "$_=" . _encode($query{$_}) } sort keys %query;
    my $uri = "$self->{uri}$job->{package}" . ($query ? "?$query" : "");
    my $res;
    for (1..2) {
        $res = $self->{http}->get($uri);
        last if $res->{success} or $res->{status} == 404;
    }
    if (!$res->{success}) {
        my $error = "$res->{status} $res->{reason}, $uri";
        $error .= ", $res->{content}" if $res->{status} == 599;
        return { error => $error };
    }

    my $hash = eval { JSON::PP::decode_json($res->{content}) } or return;
    my ($distfile) = $hash->{download_url} =~ m{/authors/id/(.+)};
    return {
        source => "cpan", # XXX
        distfile => $distfile,
        package => $job->{package},
        version => $hash->{version} || 0,
        uri => $hash->{download_url},
    };
}

1;
