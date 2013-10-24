package Blog;
use 5.010;
use Dancer2;

use MongoDB;

our $VERSION = '0.1';

hook before => sub {
	# TODO get this from the configuration file
	my $client = MongoDB::MongoClient->new(host => 'localhost', port => 27017);
	my $database   = $client->get_database( 'ourblog' );
	set mongo => $client;
	set db => $database;

	my $user = setting('db')->get_collection('users');
	#my $id     = $users->insert({ some => 'data' });

	;
	my $data       = $user->find_one({ admin => 1 });
	if (request->path ne '/setup' and not $data) {
		#request->path_info('/setup');
		#forward '/setup';
		redirect '/setup';
	}
};

get '/' => sub {
	template 'index';
};

get '/register' => sub {
	template 'register';
};

get '/setup' => sub {
	my $user = setting('db')->get_collection('users');
	my $data       = $user->find_one({ admin => 1 });
	if ($data) {
		redirect '/';
	}

	template 'register', {setup_site => 1};
};

#post '/register' => sub {
#	die 'Missing username' if not params->{username} or params->{username} !~ /^\w+$/;
#	die 'Missing Display name' if not params->{display_name} or params->{display name} !~ /\S/;
#	die 'Missing email' if not params->{email_address};
#	my $supplied_email = params->{email_address};
#	my $email = Email::Valid->address($supplied_email);
#	die 'Invalid email' if $email 
#
#
#	my %user; = (
#	foreach my $f (qw(username display_name)) {
#		$user{$f} = params->{$f};
#	}
#	$user->{password} = _hash_password($params->{initial_password});
# 
#	my $users = setting('db')->get_collection('users');
#	my $id     = $users->insert({ some => 'data' });
#};

true;
