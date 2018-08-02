package ReadFile;

use strict;
use warnings;

my $fh = undef;
my $fp = 0;
my $fs = 0;
my $path = undef;

sub new
{
	my $class        = shift;
	$path  			 = shift;
	my $self         = { name => "Flow", version => "1.0" };
	bless $self;
		
	open $fh, "<", $path;
	binmode $fh;
	
	$self->sizeCalc if $self->exists();

	return $self;
}

sub exists
{
	my $this = shift;
	return -e $path;
}

sub flock
{
	my $this = shift;
	flock($fh, 1);
	return $this;
}

sub fread
{
	my $this = shift;
	my $length = shift;
	my $buffer = "";
	read($fh, $buffer, $length);
	return $buffer;
}

sub size
{
	my $this = shift;
	return $fs;
}

sub ftell
{
	my $this = shift;
	return tell $fh;
}

sub sizeCalc
{
	my $this = shift;
	my $current = tell $fh;
	seek $fh, 0, 2;
	$fs = tell $fh;
	seek $fh, $current, 0;
	return $this;
}

sub savePos()
{
	my $this = shift;
	$fp = tell $fh;
	return $this;
}

sub getPos()
{
	my $this = shift;
	return $fp;
}

sub goPos()
{
	my $this = shift;
	seek $fh, $fp, 0;
	return $this;
}

sub fseek
{
	my $this = shift;
	my $pos = shift;
	seek $fh, $pos, 0;
	return $this;
}

sub fseekForth
{
	my $this = shift;
	my $pos = shift;
	seek $fh, $pos, 1;
	return $this;
}

sub close
{
	my $this = shift;
	close $fh;
}

sub feof
{
	my $this = shift;
	return eof($fh);
}

1;
