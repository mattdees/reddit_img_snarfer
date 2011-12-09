#!/usr/bin/env perl
# Reddit Image Snarfer
# Copyright 2011 (c) Matt Dees
# Distributed under the 2-clause BSD.

use Data::Dumper;
use HTTP::Tiny ();
use JSON::XS   ();
use File::Path qw(make_path);

my $http = HTTP::Tiny->new;

my @subreddits      = qw/ EarthPorn VillagePorn /;
my $save_dir        = "$ENV{HOME}/Pictures/RedditTest";
my $number_of_pages = 1;

make_path($save_dir); #like mkdir -p

map { load_subreddit($_) } @subreddits;

sub load_subreddit {
    my ($subreddit) = @_;
    print "\nProcessing /r/$subreddit\n---\n";
    my $res = $http->get("http://www.reddit.com/r/$subreddit/top.json?sort=top&t=all");
    if ( $res->{'status'} != 200 ) {
        return 'non-200 response recieved';
    }
    my $parsed_response = JSON::XS::decode_json( $res->{'content'} );
    my $after           = $parsed_response->{'data'}->{'after'};
    my @links;
    if ( ref $parsed_response->{'data'}->{'children'} eq 'ARRAY' ) {
        @links = @{ $parsed_response->{'data'}->{'children'} };
        my $counter = 1;
        while ( $counter < $number_of_pages ) {
            sleep 2;
            $counter++;
            print "grabbing page " . $counter . ": ";
            my $page_url = "http://www.reddit.com/r/$subreddit/top.json?sort=top&t=all&after=$after&count=" . $counter * 25;
            print $page_url . "\n";
            $res             = HTTP::Tiny->new->get($page_url);
            $parsed_response = JSON::XS::decode_json( $res->{'content'} );
            $after           = $parsed_response->{'data'}->{'after'};
            push @links, @{ $parsed_response->{'data'}->{'children'} };
            last if !$after;
        }
    }
    else {
        return 'Reddit API gave invalid response';
    }

    foreach my $link (@links) {
        my $url  = $link->{'data'}->{'url'};
        download_image( $url )
          unless ( $url !~ m@imgur\.com\/[a-z]+\.(png|jpg|gif)$@i );
    }
}

sub download_image {
    my $url = shift;
    print "Downloading $url...";
    my ($name) = ($url =~ m@imgur\.com/([a-z]+\.[a-z]{3})@i);
    my $dl = $http->mirror( $url, "$save_dir/$name" );
    print $dl->{success} ? "OK\n" : "FAILED\n";

}

sub try_extensions_on_imgur {
    my ($img_url) = @_;
    foreach my $extension (qw / png jpeg jpg /) {
        my $tmp_url = "$img_url.$extension";
        my $img_ref = HTTP::Tiny->new->get($tmp_url);
        return $img_ref, $tmp_url if $img_ref->{'status'} == 200;
    }
    return 0;
}
