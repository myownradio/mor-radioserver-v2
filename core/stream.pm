#!/usr/bin/perl

package Stream;

use DBI;
use strict;
use Time::HiRes qw(time);

use constant true  => 1;
use constant false => 0;

my $db_host = Settings::settings()->{database}->{db_hostname};
my $db_base = Settings::settings()->{database}->{db_database};
my $db_user = Settings::settings()->{database}->{db_login};
my $db_pass = Settings::settings()->{database}->{db_password};

my $dsn = "dbi:mysql:$db_base:$db_host:3306";

my $stream_id = undef;

my $dbh = undef;

sub new
{
	my $class        = shift;
	$stream_id	     = shift;
	my $self         = { name => "Stream", version => "1.0" };
	bless $self;
	return $self;
}

sub connect
{
	my $this = shift;
	$dbh = DBI->connect($dsn, $db_user, $db_pass);
	return $this;
}

sub disconnect
{
	my $this = shift;
	$dbh->disconnect();
	$dbh = undef;
	return $this;
}

sub connected
{
	my $this = shift;
	return scalar $dbh;
}

sub getTitle
{
	my $this = shift;
	my $q = $dbh->prepare("SELECT `name` FROM `r_streams` WHERE `sid` = ? LIMIT 1");
	$q->execute($stream_id);
	return 0 if $q->rows() == 0;
	my $row = $q->fetchrow_hashref();
	$q->finish();
	return $row->{name};
}

sub available
{
	my $this = shift;
	my $q = $dbh->prepare("SELECT * FROM `r_streams` WHERE `sid` = ? LIMIT 1");
	$q->execute($stream_id);
	return 0 if $q->rows() == 0;
	my $row = $q->fetchrow_hashref();
	return 0 if int($row->{status}) == 0;
	
	$q->finish();
	
	return 1;
}

sub getPlayingTrack
{
	my $this = shift;
	my $preload = shift;
	
	$dbh->do("SET NAMES 'utf8'");
	
	my $q = $dbh->prepare("SELECT * FROM `r_streams` WHERE `sid` = ? LIMIT 1");
	$q->execute($stream_id);

	return false if($q->rows() == 0);
	
	# Current stream array
	my $stream_info = $q->fetchrow_hashref();
	$q->finish();
	
	return false if $stream_info->{status} != 1;
	
	my $q = $dbh->prepare("SELECT a.*, b.`unique_id`, b.`t_order` as `t_order` FROM `r_tracks` a, `r_link` b WHERE a.`tid` = b.`track_id` AND b.`stream_id` = ? AND a.`lores` = 1 ORDER BY b.`t_order` ASC");
	$q->execute($stream_id);
	
	# Current stream's tracklist
	my $stream_tracks = $q->fetchall_hashref('t_order');
	
	# Close connection
	$q->finish();
	undef $q;
	
	# Stream duration
	my $streamLength = 0;
	foreach my $t_order (sort {$a <=> $b} keys $stream_tracks)
	{
		$stream_tracks->{$t_order}->{offset} = $streamLength;
		$streamLength += int($stream_tracks->{$t_order}->{duration});
	}
	
	return false if $streamLength == 0;
	
	# Current position
	my $stream_position = (time() * 1000 - $stream_info->{started} + $stream_info->{started_from} - $preload) % $streamLength;
	
	# Looking for current file
	foreach my $t_order (sort {$a <=> $b} keys $stream_tracks)
	{
        if (($stream_position >= $stream_tracks->{$t_order}->{offset}) && ($stream_position <= ($stream_tracks->{$t_order}->{offset} + $stream_tracks->{$t_order}->{duration})))
        {
			$stream_tracks->{$t_order}->{cursor} = $stream_position - $stream_tracks->{$t_order}->{offset};
			return $stream_tracks->{$t_order};
        }
	}	
	
	return false;
	
}

sub generatePath 
{
	my $this = shift;
	my $root = shift;
	my $track = shift;
	return sprintf("%s/ui_%d/lores_%03d.mp3", $root, $track->{'uid'}, $track->{'tid'});
}

1;