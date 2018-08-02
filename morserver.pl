#!/usr/bin/perl

use threads;
use threads::shared;
use IO::Socket::INET;
use Time::HiRes qw(time usleep);
use Redis;
use JSON;
use FindBin qw($RealBin);

use HTTP::Response;
use URI::URL;

use strict;
use warnings;

use constant true  => 1;
use constant false => 0;

use Data::Dumper;

require $RealBin . "/settings.pl";
require $RealBin . "/core/functions.pm";
require $RealBin . "/core/flow.pm";
require $RealBin . "/core/stream.pm";
require $RealBin . "/core/readfile.pm";
require $RealBin . "/core/connection.pm";

$| = 1;
$SIG{PIPE} = 'IGNORE';

my $shared_listeners 		: shared = 0;
my %shared_listeners_active : shared = ();
my @shared_gone_listeners 	: shared = ();

# Broadcasting emulation variables
my %bc_stream_cursor		: shared = ();
my %bc_stream_buffer		: shared = ();
my %bc_exit_flag			: shared = ();

my $bc_buffer_length		= 256 * 1024;

my $max_header_size			= 4096;


my $listen = IO::Socket::INET->new(LocalPort => 7777, ReuseAddr => 1, Listen => 4096);

sub stats_control
{
	while(1)
	{
		my $dbh = DBI->connect(sprintf("dbi:mysql:%s:%s:3306", 
			Settings::settings()->{database}->{db_database},
			Settings::settings()->{database}->{db_hostname}), 
			Settings::settings()->{database}->{db_login}, 
			Settings::settings()->{database}->{db_password});
		
		if($dbh) {
			while(my $l = shift @shared_gone_listeners)
			{
				$dbh->do("DELETE FROM `r_listener` WHERE `listener_id` = ?", undef, $l);
			}
			
			foreach my $key (keys %shared_listeners_active)
			{
				my $decoded = decode_json($shared_listeners_active{$key});
				$dbh->do("INSERT INTO `r_listener` SET `listener_id` = ?, `client_ip` = ?, `client_ua` = ?, `stream_id` = ?, `last_activity` = ? ON DUPLICATE KEY UPDATE `client_ip` = ?, `client_ua` = ?, `stream_id` = ?, `last_activity` = ?", undef, 
					$key, $decoded->{client_ip}, $decoded->{client_ua}, $decoded->{stream_id}, time(),
					$decoded->{client_ip}, $decoded->{client_ua}, $decoded->{stream_id}, time());
			}
			
			$dbh->disconnect();
		}
		sleep(10);
	}
}

sub handle_connection {

	++$shared_listeners;
	
	
    my $socket = shift;
    my $output = shift || $socket;
    my $exit = 0;

	
	my $listener_id = unique_listener_id();

	my $header_string = "";
	
	RUN: while (<$socket>) {

		if(length($header_string) < $max_header_size)
		{
			$header_string .= $_;
		}
		else
		{
			http_large();
			exit();
		}
	
		if( $_ eq "\r\n" )
		{
			my $r = HTTP::Response->parse( $header_string );
			my $uri = URI->new($r->{_rc});
			my %query = $uri->query_form;
			my $path = $uri->path;
			#print Dumper($path);
			my ($stream_id) = $path =~ /^\/stream_(\d+)$/i;

			$shared_listeners_active{$listener_id} = encode_json({
				'client_ip' => $r->{"_headers"}->{"x-real-ip"},
				'stream_id' => $stream_id,
				'client_ua' => $r->{"_headers"}->{"user-agent"}
			});

			broadcast_stream($stream_id, $output, $socket, $r->{"_headers"}->{"icy-metadata"}, $listener_id, $r->{"_headers"}->{"x-real-ip"});
			
			printf "Listener %s has gone out\n", $r->{"_headers"}->{"x-real-ip"};

			$exit = 1;
		}
		
		# write response data to the connected client
        # work with $_,
        # print to $output
        # set $exit to true when connection is done
        if($exit)
		{
			last RUN;
		}
    }
	delete $shared_listeners_active{$listener_id};
	push @shared_gone_listeners, $listener_id;
	--$shared_listeners;


}

sub http_responce
{
	my $icy_enabled = shift;
	my $icy_title = shift;
	my $responce = "";
	$responce .= "HTTP/1.1 200 OK\r\n";
	$responce .= "Content-Type: audio/mpeg\r\n";
	$responce .= "Server: MyOwnRadioAudioServer 1.0\r\n";
	$responce .= "icy-metadata: 1\r\n" if ($icy_enabled);
	$responce .= "icy-name: " . $icy_title . "\r\n" if ($icy_enabled);
	$responce .= "icy-notice1: This stream requires Winamp\r\n" if ($icy_enabled);
	$responce .= "icy-notice2: My Own Radio Audio Server/FreeBSD v1.0\r\n" if ($icy_enabled);
	$responce .= "icy-metaint: 8192\r\n" if ($icy_enabled);
	$responce .= "\r\n";
	return $responce;
}


sub http_404
{
	my $responce = "";
	$responce .= "HTTP/1.1 404 Not Found\r\n";
	$responce .= "Connection: keep-alive\r\n";
	$responce .= "Content-Type: text/html; charset=utf-8\r\n";
	$responce .= "Server: myownradiostreamer 1.0\r\n";
	$responce .= "\r\n";
	$responce .= "<html><body><h1>404 Not Found</h1></body></html>";
	return $responce;
}

sub http_large
{
	my $responce = "";
	$responce .= "HTTP/1.1 413 Entity Too Large\r\n";
	$responce .= "Connection: keep-alive\r\n";
	$responce .= "Content-Type: text/html; charset=utf-8\r\n";
	$responce .= "Server: myownradiostreamer 1.0\r\n";
	$responce .= "\r\n";
	$responce .= "<html><body><h1>413 Entity Too Large</h1></body></html>";
	return $responce;
}

print "myownradio.biz Broadcast Server version 1.0\n";
print "Copyright (C) 2014 by Roman Gemini\n";
print "\n";
print "Waiting for connections\n";

threads->create('stats_control')->detach();

while (my $socket = $listen->accept) {
    async(\&handle_connection, $socket)->detach;
}
