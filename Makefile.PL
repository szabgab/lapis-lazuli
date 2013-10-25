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
    ($eumm_version >= 6.3001
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
        'Dancer2'     => 0.10,
        'MongoDB'     => '0.702',
        'Template'    => '2.25',
		'Email::Sender' => '1.300006',
        'Email::Valid' => '1.192',
        'Digest::SHA'  => '5.85',
        #'Dancer2::Session::MongoDB' => '0.003',
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Blog-*' },
);
