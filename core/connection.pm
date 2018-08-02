#!/usr/bin/perl
my $use_stream_dumping		= 1;
my $stream_dumping_dir		= "/usr/domains/myownradio.biz/dump/";

sub broadcast_stream
{
	my $stream_id = int(shift);
	my $output = shift;
	my $socket = shift;
	my $header_icy = shift;
	my $listener_id = shift;
	my $header_cli = shift;
	
	my $is_first_track = 1;
	
	if($stream_id == 0)
	{
		print $output http_404();
		return 0;
	}
	
	my $stream = new Stream($stream_id);
	
	$stream->connect();
	
	unless($stream->available())
	{
		$stream->disconnect();
		print $output http_404();
		return 0;
	}
	
	my $redis = new Redis();
	my $flow = new flow();
	
	if ($use_stream_dumping == 1) {
		print "Opening dumper...\n";
		my $dump_filename = sprintf( "%s_%d.mp3", $listener_id, time() );
		open DUMP, ">", $stream_dumping_dir . $dump_filename;
	}
	
	printf "Listener %s connected to stream %d\n", $header_cli, $stream_id;

	$flow->setupIcy($header_icy)
		->setBitrate(Settings::settings()->{streamer}->{stream_bitrate})
		->setInterval(Settings::settings()->{streamer}->{icy_interval})
		->setOutput($output)
		->setTitle($stream->getTitle());

	print $output http_responce($header_icy, $stream->getTitle());
	
	$track_counter = 0;
	
	SESSION: while(1) {
		$track_counter ++;
		$time_shift = ($track_counter == 1) ? 0 : 0;
		$stream->connect() unless $stream->connected();
		return 0 unless $track = $stream->getPlayingTrack($time_shift);
		$stream->disconnect();
		my $currentStreamModified = $redis->exists(sprintf("myownradio.biz:state_changed:stream_%d", $stream_id)) ? $redis->get(sprintf("myownradio.biz:state_changed:stream_%d", $stream_id)) : 0;
		
		my $redisChecked = 0;
		my $timeControl = 0;
		my $currentUniqueId = $track->{unique_id};
		my $pathname = $stream->generatePath(Settings::settings()->{streamer}->{content_root}, $track);
		
		$flow->setTitle($track->{artist} . " - " . $track->{title});
		
		my $file = new ReadFile($pathname);
		
		return 0 unless $file->exists();
		
		my $trackStartOffset = $file->size() / $track->{duration} * $track->{cursor};
		my $trackEndTime = time() + ($track->{duration} - $track->{cursor}) / 1000;
		my $trackStartTime = time() * 1000;
		
		$file->flock()->fseek($trackStartOffset);
		
		my $buffer;
		my $skip = 0;
		FR: while(!$file->feof() && $exit == 0)
		{
			# Save current file position
			$file->savePos();
						
			if($file->getPos() > $file->size())
			{
				$file->close();
				next SESSION;
			}
						
			# Read frame header
			my $frame_header_raw = $file->fread(4);
			my $frame_header = readMp3Header($frame_header_raw);
						
			if($frame_header == -1)
			{
				my $read = $file->goPos()->fread(4096);
				my $offset = findMp3Header($read, 4);
				if($offset == -1)
				{
					if(($file->getPos() + 2048) < $file->size()) 
					{
						$file->goPos()->fseekForth(2048);
					}
				}
				else
				{
					$file->goPos()->fseekForth($offset);
				}
				next FR;
			}
        
			my $frame_size = $frame_header->{framesize};
        
			if($frame_size <= 4)
			{
				next FR;
			}
						
			my $header_contents = $file->fread($frame_size - 4);
						
			# Send frame to flow
			if($output->connected()) 
			{
				$flow->write($frame_header_raw);
				$flow->write($header_contents);
				print DUMP $frame_header_raw . $header_contents if $use_stream_dumping;
			} 
			else 
			{
				return 0;
			}
			
			my $time = time();
			# Speed control
			if($timeControl + 0.25 < $time)
			{
				my $realPosition = ($track->{duration} / $file->size() * $file->ftell()) - $track->{cursor} - $time_shift;
				my $estimatedPosition = time() * 1000 - $trackStartTime;
				my $deltaPosition = $realPosition - $estimatedPosition;
				print "Current time position difference: ", $deltaPosition, "\n";
				$timeControl = $time;
				#print $realPosition, ",", $realPosition , "\n";
				usleep($deltaPosition * 1000) if ($deltaPosition > 0);
			}
   
			# Redis control here
			if ($redisChecked + 5 < $time)
			{
				$redisChecked = $time;
				#db::query_update("UPDATE `r_listener` SET `last_activity` = ? WHERE `listener_id` = ?", array(time(), application::$listener_id));
				if( $redis->exists(sprintf("myownradio.biz:state_changed:stream_%d", $stream_id)) == 0 )
				{
					
				}
				elsif( $currentStreamModified != $redis->get(sprintf("myownradio.biz:state_changed:stream_%d", $stream_id)) )
				{
					$skip = 1;
					last FR;
				}
			}

		}
		unless ($skip) {
			my $deltaTime = $trackEndTime - time() - ($time_shift / 1000);
			usleep($deltaTime * 1000000) if $deltaTime > 0;
		}
		$file->close();
		undef $file;
	}
	
	close DUMP if $use_stream_dumping;

}

1;