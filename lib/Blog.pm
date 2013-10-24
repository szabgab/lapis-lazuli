package Blog;
use 5.010;
use Dancer2;

use Data::Dumper qw(Dumper);
use Digest::SHA qw(sha1_base64);
use Email::Valid ();
use MongoDB ();

our $VERSION = '0.1';

hook before => sub {
	# TODO get this from the configuration file
	my $client = MongoDB::MongoClient->new(host => 'localhost', port => 27017);
	my $db   = $client->get_database( 'ourblog' );
	set mongo_client => $client;
	set db => $db;

	if (request->path ne '/setup' and not _site_exists()) {
		redirect '/setup';
	}
};

hook before_template => sub {
	my $t = shift;

	if (_site_exists() and not $t->{title}) {
		my $sites_coll = setting('db')->get_collection('sites');
		my $sites  = $sites_coll->find();
		$t->{title} = $sites->next->{site_title};
	}

	my $TIMEOUT = 60;
	if (session('last_seen')) {
		if (session('last_seen') > time - $TIMEOUT) {
			my $user_id = session('user_id');
			my $users_coll = setting('db')->get_collection('users');
			my $user  = $users_coll->find_one({ _id => $user_id });
			$t->{display_name} = $user->{display_name};
			session last_seen => time;
		}
	}

	return;
};

get '/' => sub {
	template 'index';
};

get '/register' => sub {
	template 'register';
};

get '/setup' => sub {
	redirect '/' if _site_exists();

	template 'register', {setup_site => 1};
};

post '/setup' => sub {
	my $user_data = _check_new_user();

	my $sites_coll = setting('db')->get_collection('sites');
	die 'Already has a site' if _site_exists();

	my $site_title = params->{site_title};
	die 'Missing site_title' if not $site_title;
	$site_title =~ s/^\s+|\s+$//g;
	die 'Invalid site title' if not $site_title;
	my $site_id = $sites_coll->insert({ site_title => $site_title });
	# TODO without the quotes we get  huge and unusable stack trace
	#die "$site_id";

	$user_data->{admin} = 1;
	my $users_coll = setting('db')->get_collection('users');
	my $user_id    = $users_coll->insert($user_data);

	redirect '/';
};

post '/register' => sub {
	my $user_data = _check_new_user();

	my $users_coll = setting('db')->get_collection('users');
	my $user_id    = $users_coll->insert($user_data);

	redirect '/';
};


get '/login' => sub {
	template 'login';
};

post '/login' => sub {
	die 'Missing username' if not params->{username};
	die 'Missing password' if not params->{password};
	my %user = (
		username => params->{username},
		password => sha1_base64(params->{password}),
	);

	my $users_coll = setting('db')->get_collection('users');
	my $user_id    = $users_coll->find_one(\%user);
	die "Could not authenticate" if not $user_id;

	session last_seen => time;
	session user_id => $user_id->{_id};

	#forward '/'; # cannot forward, probably because this is a POST and / is only defined for GET
	#redirect '/'; # the cookie is not set!
	template 'index'; # not nice, but it works for now
};

get '/logout' => sub {
	context->destroy_session;
	redirect '/';
};


sub _check_new_user {
	die 'Missing username' if not params->{username} or params->{username} !~ /^\w+$/;
	die 'Missing Display name' if not params->{display_name} or params->{display_name} !~ /\S/;
	die 'Missing email' if not params->{email_address};
	my $supplied_email = lc params->{email_address};
	$supplied_email =~ s/^\s+|\s+$//g;
	my $email = Email::Valid->address($supplied_email);
	die 'Invalid email' if not $email or $email ne $supplied_email;
	die 'Missing password' if not params->{initial_password} or not params->{password_confirm};
	die 'Passwords differ' if params->{initial_password} ne params->{password_confirm};

	my %user = (
		username     => params->{username},
		display_name => params->{display_name},
		password     => sha1_base64(params->{initial_password}),
	);
	return \%user;
}

sub _site_exists {
	my $sites_coll = setting('db')->get_collection('sites');
	if ($sites_coll) {
		my $sites  = $sites_coll->find();
		return 1 if $sites->all;
	}
	return;
}


true;
