package Google::GeocodingAPI::Proxy;
use strict;
use Dancer ':syntax';
use Dancer::Plugin::REST;
use Digest::SHA1  qw/ sha1_hex /;
use Encode;
use JSON::Syck ();
use LWP::Curl;
use Path::Class;
use URI;
use Storable;
use Class::Date qw/ date /;
our $VERSION = '0.1';

set serializer => 'JSON';

our $root = dir('data-files');
-d $root || $root->mkpath( 0, 0777 );

get '/' => sub {
    my $address = param 'address';
    my $force = param 'force';

    my $addr = $address;
    Encode::_utf8_off( $addr );
    my $sha = sha1_hex( $addr );
    my @subdir = split //, substr( $sha, 0, 6 );
    my $dir = $root->subdir( @subdir );
    -d $dir || $dir->mkpath( 0, 0777 );

    my $file = $dir->file( $sha )->stringify;
    if ( $force == 1 || ! -f $file ){
        # http://code.google.com/intl/zh-CN/apis/maps/documentation/geocoding/index.html#StatusCodes
        my $uri = URI->new("http://maps.google.com/maps/api/geocode/json");
        $uri->query_form( 'address' => $address, 'sensor' => 'false' );
        printf STDERR "wget %s\n", $uri;

        my $curl = new LWP::Curl;
        my $json = $curl->get( $uri->as_string );
        my $gmap = JSON::Syck::Load( $json );

        my $status = $gmap->{'status'};
        my $lat = $gmap->{'results'}[0]{'geometry'}{'location'}{'lat'};
        my $lng = $gmap->{'results'}[0]{'geometry'}{'location'}{'lng'};
        printf STDERR "status: %s; lat/lng: %s\n", $status, $lat, $lng;

        my $yaml = { address => $address, gmap => $gmap, created_at => time };
        store $yaml, $file;
    }
    
    my $yaml = retrieve( $file );
    my $res = { 'address' => $yaml->{'address'} };
    my $gmap = $yaml->{'gmap'};
    if ( $gmap->{'status'} eq 'OK' ){
        $res->{'lat'} = $gmap->{'results'}[0]{'geometry'}{'location'}{'lat'};
        $res->{'lng'} = $gmap->{'results'}[0]{'geometry'}{'location'}{'lng'};
        $res->{'last'} = date( $yaml->{'created_at'} )->string;
    }else{  
        $res->{'error'} = $gmap->{'status'};
    }
    return status_ok($res);
};

true;
