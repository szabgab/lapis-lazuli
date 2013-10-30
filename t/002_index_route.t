use Test::More tests => 7;
use strict;
use warnings;

use MongoDB;

# the order is important
use Blog;
use Dancer2::Test apps => ['Blog'];


$ENV{TEST_DB}   = "test_" . time;
$ENV{TEST_HOST} = "localhost:27017";

diag $ENV{TEST_DB};

# Usually we want to clean up after ourselves and remove the test
# database, but there can be cases when we would like it to stay
# for that case we can run the test using
#    KEEP=1 prove -vl t/002_index_route.t 
END {
	unless ($ENV{KEEP}) {
		my $db = Blog::DB->instance(host => $ENV{TEST_HOST}, database => $ENV{TEST_DB})->db;
		$db->drop;
	}
}

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
	plan tests => 2;
	my $response = dancer_response POST => '/setup', {
		params => {
			site_title       => "Test Site",
			username         => 'test_admin',
			email_address    => 'szabgab@cpan.org',
			initial_password => 'admin_pw',
			password_confirm => 'admin_pw',
		},
	};
	#diag explain $response;
	like $response->content, qr/Congratulations. You've finished setting up the web site./;
	like $response->content, qr/Test Site/;
};

subtest '/' => sub {
	plan tests => 2;
	my $response = dancer_response GET => '/';
	like $response->content, qr/Test Site/;
	like $response->content, qr/No posts yet/;
};


subtest '/register' => sub {
	plan tests => 1;
	my $response = dancer_response GET => '/register';
	like $response->content, qr/Initial Password:/;
};

subtest '/register' => sub {
	plan tests => 2;
	my $response = dancer_response POST => '/register', {
		params => {
			username         => 'test_admin',
			email_address    => 'szabgab@gmail.com',
			initial_password => 'some_pw',
			password_confirm => 'some_pw',
		},
	};
	#diag explain $response;
	is $response->status, 200;
	like $response->content, qr/Username already taken/;
};

subtest '/register' => sub {
	plan tests => 2;
	my $response = dancer_response POST => '/register', {
		params => {
			username         => 'other_admin',
			email_address    => 'szabgab@cpan.org',
			initial_password => 'some_pw',
			password_confirm => 'some_pw',
		},
	};
	#diag explain $response;
	is $response->status, 200;
	like $response->content, qr/Email already used/;
};




