use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
	NAME                => 'Blog',
	AUTHOR              => q{Gabor Szabo <gabor@szabgab.com>},
	VERSION_FROM        => 'lib/Blog.pm',
	ABSTRACT            => 'A Blog engine',
	LICENSE             => 'perl',
	PL_FILES            => {},
	PREREQ_PM => {
		'Test::More'    => 0,
		'YAML'          => '0.84',
		'Dancer2'       => 0.10,
		'MongoDB'       => '0.702',
		'Template'      => '2.25',
		'Email::Sender' => '1.300006',
		'Email::Valid'  => '1.192',
		'Digest::SHA'   => '5.85',
		#'Dancer2::Session::MongoDB' => '0.003',
		'Moo'              => '1.003001',
		'MooX::late'       => '0.014',
		'MooX::Singleton'  => '1.20',
		'MooX::Types::MooseLike::Base' => '0.25',
		'Text::Markdown'   => '1.000031',
		'Time::HiRes'      => '1.9725',


		'Net::OpenID::Consumer' => 0,
		'LWP::UserAgent'        => 0,
		'Cache::File'           => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'Blog-*' },
);
