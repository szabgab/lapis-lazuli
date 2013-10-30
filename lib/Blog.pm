package Blog;
use 5.010;
use Dancer2;

use Data::Dumper qw(Dumper);
use DateTime ();
use Digest::SHA qw(sha1_base64);
use Email::Valid ();

use Blog::Email;
use Blog::DB;
use Blog::Audit;

our $VERSION = '0.1';

#hook on_route_exception => sub {
#	my ($context, $error) = @_;
#	forward '/';
#	return;
#};

hook before => sub {
	# TODO get this from the configuration file
	my $database = $ENV{TEST_DB}   || config->{blog}{database_name};
	my $host     = $ENV{TEST_HOST} || config->{blog}{database_host};
	set db => Blog::DB->instance(host => $host, database => $database)->db;

	set email => Blog::Email->new(url => request->uri_base);

	if (not _site_exists()) {
		my $path = request->path;
		if ($path ne '/setup' and $path !~ m{^(/css/)} ) {
			redirect '/setup';
		}
	}

	if (request->path =~ m{^/u/} and not logged_in()) {
		redirect '/'; # TODO better handling of timeout
	}

	if (request->path =~ m{^/a/}) {
		if (not logged_in()) {
			return forward '/message/require_admin_login';
		}
		my $user_id = session('user_id');
		my $users_coll = setting('db')->get_collection('users');
		my $user  = $users_coll->find_one({ _id => $user_id });
		if (not $user->{admin}) {
			return forward '/message/require_admin_login';
		}
	}
};

hook before_template => sub {
	my $t = shift;

	if (_site_exists() and not $t->{title}) {
		my $sites_coll = setting('db')->get_collection('sites');
		my $sites  = $sites_coll->find();
		$t->{title} = $sites->next->{site_title};
	}

	if (logged_in()) {
		my $user_id = session('user_id');
		my $users_coll = setting('db')->get_collection('users');
		my $user  = $users_coll->find_one({ _id => $user_id });
		$t->{user}{display_name} = $user->{display_name} || $user->{username};
		$t->{user}{admin} = $user->{admin};
	}

	unless (request->path =~ m{^/setup}) {
		$t->{show_sidebar} = 1;
	}

	return;
};

get '/reset-password' => sub {
	template 'reset_password';
};

get '/reset-password/:id/:code' => sub {
	template 'set_password';
};

post '/reset-password/:id/:code' => sub {
	my $id = params->{id};
	my $code= params->{code};

	my $users_coll = setting('db')->get_collection('users');
	my $user = $users_coll->find_one({
			_id => MongoDB::OID->new(value => $id),
			password_reset_code => $code,
	});
	die "Could not find user"
		if not $user;

	die "No password provided" if not params->{new_password};
	my $password = params->{new_password};
	die "Password need to be confirmed" if not params->{password_confirm};
	die "Not the same passwords" if $password ne params->{password_confirm};
	$password = sha1_base64($password);

	$users_coll->update({
			_id => MongoDB::OID->new(value => $id),
			password_reset_code => $code,
	},{
		'$set' => { password => $password },
		'$unset' => {
			password_reset_code => '',
			password_reset_ts => '',
		},
	});

	template 'message', { new_password_set => 1 };
};

post '/reset-password' => sub {
	my $users_coll = setting('db')->get_collection('users');
	my $username = params->{username};
	my $email    = params->{email};
	my $user;
	if ($username) {
		$user = $users_coll->find_one({ username => $username });
		die "Could not find the user based on the username"
			if not $user;
	} elsif ($email) {
		$user = $users_coll->find_one({ 'emails.email'  => $email });
		die "Could not find the user based on the email address."
			if not $user;
	} else {
		die "Need either username or email address";
	}
	die "This user does not have an e-mail"
		if not $user->{emails}[0]{email};
	# TODO shall we check if the e-mail is verified?

	# TODO shall we set it verified if the user has reset the password using
	# this e-mail address?

	my $reset_code = _generate_code();
	$users_coll->update({ _id => $user->{_id} }, {
		'$set' => {
			password_reset_code => $reset_code,
			password_reset_ts   => DateTime->now,
		},
	});

#die Dumper $user;

	setting('email')->send_password_set_code(
		code  => $reset_code,
		email => $user->{emails}[0],
		id    => "$user->{_id}",
		name  => ($user->{display_name} || $user->{username}),
	);

	template 'message', { reset_pw_sent => 1 };
};

get '/message/:code' => sub {
	template 'message', { params->{code} => 1 };
};

any ['get', 'post'] => '/' => sub {
	my $pages_coll = setting('db')->get_collection('pages');
	my $users_coll = setting('db')->get_collection('users');
	my $all_pages = $pages_coll->find( { status => 'published' } );
	my @pages;
	while (my $p = $all_pages->next) {
		$p->{id} = $p->{_id};
		my $user = $users_coll->find_one({ _id => $p->{author_id} });
		$p->{username}     = $user->{username};
		$p->{display_name} = $user->{display_name} || $user->{username};
		push @pages, $p;
	 };
	template 'index', {pages => \@pages};
};

get '/register' => sub {
	template 'register';
};

get '/setup' => sub {
	redirect '/' if _site_exists();

	template 'setup', {setup_site => 1};
};

post '/setup' => sub {

	my $sites_coll = setting('db')->get_collection('sites');
	die 'Already has a site' if _site_exists();

	my $site_title = params->{site_title};
	die 'Missing site_title' if not $site_title;
	$site_title =~ s/^\s+|\s+$//g;
	die 'Invalid site title' if not $site_title;
	my $site_id = $sites_coll->insert({ site_title => $site_title });
	# TODO without the quotes we get  huge and unusable stack trace
	#die "$site_id";

	my $users_coll = setting('db')->get_collection('users');
	$users_coll->ensure_index({ username => 1 }, {
		unique => boolean::true,
	});

	my $user_data = _check_new_user();
	$user_data->{admin} = 1;
	my $user_id    = $users_coll->insert($user_data);

	#my $pages_coll = setting('db')->get_collection('pages');
	#$pages_coll->ensure_index({ basename => 1 }, {
	#	unique => boolean::true,
	#});

	template 'message', { welcome => 1, show_sidebar => 1 };
	#redirect '/';
};

post '/register' => sub {
	my $user_data = _check_new_user();

	my $users_coll = setting('db')->get_collection('users');
	my $u = $users_coll->find_one({ username => $user_data->{username} });
	if ($u) {
		die "Username already taken";
	}
	my $u2 = $users_coll->find_one({ 'emails.email' => $user_data->{emails}[0]{email} });
	if ($u2) {
		die "Email already used";
	}

	my $user_id    = $users_coll->insert($user_data);
	Blog::Audit->save(
		user => $user_id,
		what => 'register',
		subject => '',
	);
#die Dumper $user_id;

	setting('email')->send_validation_code(
		email => $user_data->{emails}[0],
		id   => "$user_id",
		name => $user_data->{display_name},
	);

	template 'message', { 'just_registered' => 1 };
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
	#redirect '/', 303; # the cookie is not set!
	template 'message', {logged_in => 1} ;
};

get '/validate-email/:id/:code' => sub {
	my $user_id = params->{id};
	my $validation_code = params->{code};

	my $users_coll = setting('db')->get_collection('users');
	my $res = $users_coll->update({
			_id => MongoDB::OID->new(value => $user_id),
			emails => {
				'$elemMatch' => { verify_code => $validation_code }, 
			}
		},
		{
			'$set' => { 'emails.$.verified' => boolean::true }, 
			'$unset' => { 'emails.$.verify_code' => '' },
		});
	#die Dumper $res;
	if ($res->{updatedExisting}) {
		template 'message', { email_verified => 1 };
	} else {
		template 'message', { could_not_verify_email => 1 };
	}
};

get '/logout' => sub {
	context->destroy_session;
	redirect '/';
};


get '/tag/:tag' => sub {
	my $tag = params->{tag};
	my $pages_coll = setting('db')->get_collection('pages');
	my $pages = $pages_coll->find({ tags => $tag });
	template 'index', {pages => [map {$_->{id} = $_->{_id}; $_ } $pages->all]};
};


get '/u/create-post' => sub {
	my $id = params->{id};
	if ($id) {
		my $pages_coll = setting('db')->get_collection('pages');
		my $page  = $pages_coll->find_one({ _id => MongoDB::OID->new(value => $id) });
		die "Could not find page for id '$id'" if not $page;
		if ($page->{author_id} ne session('user_id')) {
			die "You cannot edit someone elses page!";
		}
		$page->{id} = $page->{_id};
		if ($page->{tags}) {
			$page->{tags} = join ', ', @{ $page->{tags} };
		}
		return template 'editor', { page => $page };
	}
	template 'editor';
};

post '/u/create-post' => sub {
	# TODO check parameters

	# TODO:
	# make sure basename is unique for the path it will be displayed
	# at
	# display: user_yyyy_mm   (there could be other strategies)
	# fetch all the pages with the same basename and check the full path of each one of them.


	my $pages_coll = setting('db')->get_collection('pages');

	my %data;
	$data{updated_timestamp} = DateTime->now;
	my $page_id = params->{id};
	my $user_id = session('user_id');
	if ($page_id) {
		my $page  = $pages_coll->find_one({ _id => MongoDB::OID->new(value => $page_id) });
		die "This is someone elses post!" if $page->{author_id} ne $user_id;
		%data = %$page;
	}

	$data{$_} = params->{$_} for qw(title basename abstract body status);
	my $tags = params->{tags};
	if ($tags) {
		$data{tags} = [ map { s{^\s+|\s+$}{}; $_ } split /,/, $tags ];
	}

	if ($page_id) {
		$pages_coll->update({ _id => MongoDB::OID->new(value => $page_id)}, \%data);
		return 1;
	}

	# TODO: add published_timestamp

	# New post
	my $users_coll = setting('db')->get_collection('users');
	my $user = $users_coll->find_one({ _id => $user_id });
	die 'Could not find user' if not $user;
	# TODO, check if the user has the right to create a page?
	$data{author_id} = $user_id;
	$data{created_timestamp} = DateTime->now;

	# blogs.perl.org style:
	$data{permalink} = sprintf '/users/%s/%s/%s/%s.html',
		$user->{username},
    	$data{created_timestamp}->year,
    	$data{created_timestamp}->month,
		$data{basename};
	$page_id = $pages_coll->insert( \%data );
	return 1;	
};

get '/u/list-posts' => sub {
	my $pages_coll = setting('db')->get_collection('pages');
	my $all_pages = $pages_coll->find( { author_id => session('user_id') } );

	template 'list_pages', {pages => [map {$_->{id} = $_->{_id}; $_ } $all_pages->all]};
};

get '/a/list-posts' => sub {
	my $pages_coll = setting('db')->get_collection('pages');
	my $all_pages = $pages_coll->find( );

	template 'list_pages', {
		pages => [map {$_->{id} = $_->{_id}; $_ } $all_pages->all],
		admin_list => 1};
};


get '/u/edit-profile' => sub {
	my $user_id = session('user_id');
	my $users_coll = setting('db')->get_collection('users');
	my $user  = $users_coll->find_one({ _id => MongoDB::OID->new(value => "$user_id") });
	$user->{id} = "$user->{_id}";
	template 'edit-profile', { the_user => $user };
};
post '/u/edit-profile' => sub {
	my %data = (
		#username     => params->{username},
		display_name => params->{display_name},
		website      => params->{website},
		about        => params->{about},
	);

	if (params->{new_password}) {
		my $password = params->{new_password};
		die "Password need to be confirmed" if not params->{password_confirm};
		die "Not the same passwords" if $password ne params->{password_confirm};
		$data{password} = sha1_base64($password);
	}

	#die if not $display_name or $display_name !~ /\S/;

	my $user_id = session('user_id');
	my $users_coll = setting('db')->get_collection('users');
	$users_coll->update({ _id => MongoDB::OID->new(value => "$user_id") },
		{ '$set' => \%data },
	);

	my $user  = $users_coll->find_one({ _id => MongoDB::OID->new(value => "$user_id") });
	$user->{id} = "$user->{_id}";
	template 'message', {
		profile_updated => 1,
		the_user => $user,
	};
};

get '/users/:username/:page' => sub {
	my $username = params->{username};
	my $page = params->{page};
	if ($page eq 'profile') {
		my $users_coll = setting('db')->get_collection('users');
		my $user  = $users_coll->find_one({ username => $username });
		if (not $user) {
			return template 'message', { no_such_username => 1 };
		}

		return template 'profile', { the_user => $user };
	}
	die 'Not implemented';
};

get qr{^/users/.*} => sub {
	my $path = request->path;
	my $pages_coll = setting('db')->get_collection('pages');
	my $page = $pages_coll->find_one( { permalink => $path } );
	pass if not $page;	

	template 'page', {
		page => $page,
	}
};


get '/a/audit' => sub {
	my $audit_coll = setting('db')->get_collection('audit');
	my $all_entries = $audit_coll->find();

	template 'list_audit', {audit => [ $all_entries->all ] };
};

get '/a/list-users' => sub {
	my $users_coll = setting('db')->get_collection('users');
	my $all_users = $users_coll->find();

	template 'list_users', {users => [map {$_->{id} = $_->{_id}; $_ } $all_users->all]};
};

get '/a/user' => sub {
	my $user_id = params->{id};
	my $users_coll = setting('db')->get_collection('users');
	my $user  = $users_coll->find_one({ _id => MongoDB::OID->new(value => $user_id) });
	$user->{id} = "$user->{_id}";

	my $pages_coll = setting('db')->get_collection('pages');
	my $all_pages = $pages_coll->find( { author_id => $user_id } );
	template 'admin_user', {
		the_user => $user,
		pages => [map {$_->{id} = $_->{_id}; $_ } $all_pages->all],
	};
};

get '/a/delete-user' => sub {
	my $user_id = params->{id};
	my $users_coll = setting('db')->get_collection('users');
	my $user  = $users_coll->find_one({ _id => MongoDB::OID->new(value => $user_id) });
	my $ret = $users_coll->remove({ _id => MongoDB::OID->new(value => $user_id) });

	Blog::Audit->save(
		user => $user_id,
		what => 'delete',
		subject => "User $user->{username} deleted",
	);

	#die Dumper $ret;
	#die "Could not find user" if not $user;
	#die Dumper $user;
	#$user->delete;
	template 'message', { user_deleted => 1 };
};


sub _check_new_user {
	die 'Missing username' if not params->{username} or params->{username} !~ /^\w+$/;
	die 'Missing email' if not params->{email_address};
	my $supplied_email = lc params->{email_address};
	$supplied_email =~ s/^\s+|\s+$//g;
	my $email = Email::Valid->address($supplied_email);
	die 'Invalid email' if not $email or $email ne $supplied_email;
	die 'Missing password' if not params->{initial_password} or not params->{password_confirm};
	die 'Passwords differ' if params->{initial_password} ne params->{password_confirm};

	my $now = DateTime->now;

	my %user = (
		username     => params->{username},
		display_name => (params->{display_name} || params->{username}),
		password     => sha1_base64(params->{initial_password}),
		emails        => [ {
			email    => $email,
			verified => boolean::false,
			verify_code => _generate_code(),
			submitted_ts => $now,
			# so we can remove e-mails that were not verified for a long time
		}],
		registration_ts => $now,
	);
	return \%user;
}

sub _generate_code {
	my @chars = ('a' .. 'z', 'A' .. 'Z', 0 .. 9);
	my $code = '';
	$code .= $chars[ int rand scalar @chars ] for 1..20;
	return $code;
}


sub _site_exists {
	my $sites_coll = setting('db')->get_collection('sites');
	if ($sites_coll) {
		my $sites  = $sites_coll->find();
		return 1 if $sites->all;
	}
	return;
}

sub logged_in {
	my $TIMEOUT = 24*60*60;

	return if not session('last_seen');
	return if session('last_seen') < time - $TIMEOUT;

	session last_seen => time;
	return 1;
}

true;

__END__

=pod

=head1 NAME

Blog - just a blog

=head1 INSTALLATION

It requires MongoDB to be installed.
On Ubuntu that means mongodb and mongodb-dev packages.

Install cpan minus:

   $ curl -L http://cpanmin.us | perl - App::cpanminus

Then install the Blog:

    $ cpanm Blog

=head1 SETUP

Once the application is installed the database needs
to be configured:

TBD

=head1 DESCRIPTION

=head2 Registration

Required fields:

   Username: *
   Email Address: *
   Initial Password: *
   Password Confirm: *

   CAPTCHA

Try to fetch a Gravatar based on the
e-mail address and save it as the default
user picture.

Once the registration is submitted we
show a page called "Profile Created"
and send e-mail with confirmation link.
The link contains the user_id and a  token
which is a long random string.

Clicking ont the confirmation link the 
user gets to a page saying
"Thanks for validating the e-mail address.
Please log in"

=head2 Log in

  Username:
  Password:
  "Log In" button

Do we need a Rememeber me checkbox?

=head2 User Profile

Additional information the user can provide
in their profile:

   Display Name:
   About: (text box)
   Website URL:

=head2 Edit Profile

  Username is unique and it cannot be changed.
  Display Name:
  Email address:
  Website
  New Password:
  Confirm Password:
  Userpic (Browse to upload)
  About (text box)
  Save (button)

  An e-mail address can only belong to one user

  TODO: Allow the user to have several e-mail addresses on file,
        with one of them being the primary address.


  Allow the user to "Reset Password" by typing in either the username or the e-mail address
  and getting an e-mail with a code including a link to a password reset page. 

=cut

