use Test::More tests => 9;
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

my $title = "What is Lorem Ipsum?";
my $text = <<"END_TEXT";
Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum
END_TEXT
# Source: http://www.lipsum.com/

subtest '/u/create-post' => sub {
	plan tests => 4;
	my $cnt = 0;


	# login
	my $r1 = dancer_response GET => '/login';
	like $r1->content, qr{<input type="submit" value="Log in" />};
	my $r2 = dancer_response POST => '/login', {
		params => {
			username => $users[0]{username},
			password => $users[0]{initial_password},
		},
	};
	like $r2->content, qr{Thanks $users[0]{username} for logging in};

	my ($cookie) =  $r2->header('set-cookie') =~ /(dancer.session=[^;]+);/;
	#diag $cookie;
	#my ($id) = (split /=/, $cookie)[1];
	#diag $id;
	#ok -e "sessions/$id.yml";
	# make sure we have the cookie
	$ENV{HTTP_COOKIE} = $cookie;
	my $r3 = dancer_response GET => '/';
	#, {
	#	headers => [
			#[ 'Cookie' => $r2->{headers}{'set-cookie'} ],
	#		[ 'Cookie' => $cookie ],
	#	],
	#};
	like $r3->content, qr{<li><a href="/u/create-post">Create Post</a></li>};
	#diag explain $r3->content;

	# post an article  article
	$cnt++;
	# just andomly splt up the text to abstract and body
	my $split = int rand length $text;
	my $r4 = dancer_response POST => '/u/create-post', {
		params => {
			title => "$title ($users[0]{username})",
			basename => "post-$cnt",
			abstract => substr($text, 0, $split),
			body     => substr($text, $split),
			status   => 'published',
		},
	};
	is $r4->content, 1;

};



