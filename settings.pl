package Settings;

sub settings
{
	return {
		'database' => {
			'db_hostname' => 'localhost',
			'db_login'    => 'root',
			'db_password' => '',
			'db_database' => 'myownradio'
		},
		'streamer' => {
			'stream_bitrate' => 256000,
			'icy_interval' 	 => 8192,
			'content_root'	 => '/media/www/myownradio.biz/content'
		},
		'server' => {
			'max_header_size' => 8192,
		}
	};
}

1;