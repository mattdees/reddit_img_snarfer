#!/usr/bin/env perl
# Reddit Image Snarfer
# Copyright 2011 (c) Matt Dees
# Distributed under the 2-clause BSD.


use Data::Dumper;
use HTTP::Tiny ();
use JSON::XS   ();
use Image::Info ();
use File::Path qw(make_path);

my @subreddits      = qw/ EarthPorn VillagePorn /;
my $save_dir        = "$ENV{HOME}/Pictures/RedditTest";
my $number_of_pages = 10;

make_path($save_dir); #like mkdir -p

map { load_subreddit($_) } @subreddits;

sub load_subreddit {
    my ($subreddit) = @_;
    print "\nProcessing /r/$subreddit\n---\n";
    my $res = HTTP::Tiny->new->get("http://www.reddit.com/r/$subreddit/top.json?sort=top&t=all");
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
        my $name = $link->{'data'}->{'title'};
        download_image( $url, $name )
          unless ( $url !~ m@imgur\.com\/[a-z]+\.(png|jpg|gif)$@i );
    }
}

sub download_image {
    my ( $img_url, $name ) = @_;
    print "Downloading $img_url...\n";
    my $img_ref = HTTP::Tiny->new->get($img_url);

    # try grabbing url .png and .jpg incase the first download returns a page
    if ( $img_url =~ /imgur.com/ && $img_ref->{'headers'}->{'content-type'} =~ /text\/html/ ) {
        ( $img_ref, $img_url ) = try_extensions_on_imgur($img_url);
        if ( !$img_ref ) {
            print "Failure: image could not be downloaded.\n";
            return;
        }
    }
    if ( $img_ref->{'status'} != 200 ) {
        print "Failure: image returned http status code " . $img_ref->{'status'} . "\n";
        return;
    }
    process_img( $img_ref->{'content'}, $img_url, $name );

    #	print Dumper $img_ref;
}

sub process_img {
    my ( $img_file_contents, $img_url ) = @_;
    my $name = $img_url;
    $name =~ s/^(.+\/){1,}(.+)$/$2/;
#    my ($extension) = $img_url =~ /\.([a-zA-Z]{3,4})$/;
    my $image_filename = "$save_dir/$name";
    $image_filename =~ s/\.([a-zA-Z]{3,4})//;
    my $img_type = Image::Info::image_type(\$img_file_contents)->{'file_type'};
    print "Determined file type to be $img_type.\n";
    if ( $img_type eq 'JPEG' ) {
        $image_filename .= '.jpg';
    }
    elsif ( $img_type eq 'PNG' ) {
        $image_filename .= '.png';
    }
    elsif ( $img_type eq 'GIF') {
        $image_filename .= '.gif';
    }
    else {
        print "File is not a valid image skipping.\n";
        return;
    }
    print "Saving to $image_filename\n";
    open( my $img_file_fh, '>', $image_filename ) || print "FAILED Opening File for Writing: $!\n";
    print $img_file_fh $img_file_contents;
    close $img_file_fh || die $!;
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
