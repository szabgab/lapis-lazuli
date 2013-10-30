use Test::More tests => 3;
use strict;
use warnings;

$ENV{TEST_DB}   = "test_" . time;
$ENV{TEST_HOST} = "localhost:27017";

use MongoDB;

END {
	my $db = Blog::DB->instance(host => $ENV{TEST_HOST}, database => $ENV{TEST_DB})->db;
	$db->drop;
}

# the order is important
use Blog;
use Dancer2::Test apps => ['Blog'];

subtest 'root' => sub {
	plan tests => 2;
	my $response = dancer_response GET => '/';
	is $response->status, 302;
	is $response->headers->{location}, 'http://localhost/setup';
};

subtest '/setup' => sub {
	plan tests => 1;
	my $response = dancer_response GET => '/setup';
	like $response->content, qr/Welcome to the installation tool/;
};

subtest '/setup' => sub {
	plan tests => 1;
	my $response = dancer_response POST => '/setup', {
		params => {
			site_title       => "Test",
			username         => 'test_admin',
			email_address    => 'szabgab@cpan.org',
			initial_password => 'admin_pw',
			password_confirm => 'admin_pw',
		},
	};
	#diag explain $response;
	like $response->content, qr/Congratulations. You've finished setting up the web site./;
};


