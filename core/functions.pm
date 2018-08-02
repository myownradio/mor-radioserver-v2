#!/usr/bin/perl

    sub findMp3Header
    {
		my $data = shift;
		my $starting = shift;
		
		
        if (length($data) < 4)
        {
            return -1;
        }

        for (my $n = $starting; $n < length($data) - 3; $n ++ )
        {
            if (readMp3Header(substr($data, $n, 4)) != -1)
            {
                return $n;
            }
        }
        return -1;
    }

    sub readMp3Header
    {
		my $header = shift;
		
        if (length($header) < 4)
        {
            return -1;
        }

        # Convert header string to bits
        my $header_bits = unpack("N", $header);
		
        # Check bits correctness
        if (($header_bits & 0xFFE << 20) != 0xFFE << 20)
        {
            return -1;
        }

        # Seems to be ok. Trying to decode
        my $mp3_header;

        my $version_array = ['MPEG Version 2.5 (not an official standard)',
            'Wrong Version', 'MPEG Version 2', 'MPEG Version 1'];

        my $header_array = ['Unknown', 'Layer III', 'Layer II', 'Layer I'];

        my $bitrate_array = [undef, 32, 40, 48, 56, 64, 80, 96, 112,
            128, 160, 192, 224, 256, 320, undef];

        my $sampling_array = [44100, 48000, 32000, "Unknown"];
        my $channels_array = ["Stereo", "Joint Stereo", "Dual", "Mono"];
        my $emphasis_array = ["None", "50/15", undef, "CCIT J.17"];

		
        if ((($header_bits & 0xF << 12) >> 12) == 0xF)
        {
            return -1;
        }


        $mp3_header->{version} 		= $version_array->[($header_bits & 0x3 << 19) >> 19];
        $mp3_header->{layer} 		= $header_array->[($header_bits & 0x3 << 17) >> 17];
        $mp3_header->{crc} 			= (($header_bits & 0x1 << 15) >> 15) ? "No" : "True";
        $mp3_header->{bitrate} 		= $bitrate_array->[($header_bits & 0xF << 12) >> 12];
        $mp3_header->{samplerate} 	= $sampling_array->[($header_bits & 0x3 << 10) >> 10];
        $mp3_header->{padding} 		= (($header_bits & 0x1 << 9) >> 9) ? "Yes" : "No";
        $mp3_header->{channels} 	= $channels_array->[($header_bits & 0x3 << 6) >> 6];
        $mp3_header->{emphasis} 	= $emphasis_array->[$header_bits & 0x3];


        # Skip frame if not Layer III
        if ($mp3_header->{layer} ne "Layer III")
        {
            return -1;
        }

        # Skip if wrong sampling rate
        if ($mp3_header->{samplerate} != 44100)
        {
            return -1;
        }

        $mp3_header->{framesize} = int(144000 * $mp3_header->{bitrate} / $mp3_header->{samplerate});

        if ($mp3_header->{framesize} == 0)
        {
            return -1;
        }

        $mp3_header->{padding} eq "Yes" ? $mp3_header->{framesize} ++ : undef;

        return $mp3_header;
    }

	sub long2ip
	{
		#my @long = ;
		return join ".", unpack "C[4]", shift;
	}

	sub unique_listener_id
	{
		my $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
		my $chars_cnt = 6;
		my $new_id;
		
		do
		{
			$new_id = "";
			for my $i (1..$chars_cnt)
			{
				$new_id .= substr($chars, int(rand(length($chars)-1)), 1);
			}
		}
		while(exists($shared_listeners_active{$new_id}));
		
		return $new_id;
	}
	
return true;