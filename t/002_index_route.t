use Test::More tests => 8;
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

# register 3 users
# post 2 articles each with long text
# check if they show up correctly, check paging (set the page size to 4)

my @users = (
	{
		username => 'bar',
		email_address => 'bar@examples.com',
		initial_password => 'bar_pw',
		password_confirm => 'bar_pw',
	},
	{
		username => 'zorg',
		email_address => 'zorg@examples.com',
		initial_password => 'zorg_pw',
		password_confirm => 'zorg_pw',
	},
	{
		username => 'foo',
		email_address => 'foo@examples.com',
		initial_password => 'foo_pw',
		password_confirm => 'foo_pw',
	},
);

subtest '/register' => sub {
	plan tests => 2*@users;
	foreach my $u (@users) {
		my $response = dancer_response POST => '/register', {
			params => $u,
		};
		is $response->status, 200;
		#diag $response->content;
		like $response->content, qr/Thank you for registering./;
	}
};



