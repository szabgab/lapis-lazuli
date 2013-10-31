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

my @site_configuration = (
	{
		display => 'From name',
		name    => 'from_name',
		type    => 'text',
		default => '',
	},
	{
		display => 'From email',
		name    => 'from_email',
		type    => 'text',
		default => '',
	},
	{
		display => 'Page size',
		name    => 'page_size',
		type    => 'int',
		default => 10,
	},
);

sub _site_config {
	my $db = Blog::DB->instance->db;
	my $config_coll = setting('db')->get_collection('config');
	return $config_coll->find_one({ name => 'site_config' });
}


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
	return _error('could_not_find_user') if not $user;

	return _error('no_password') if not params->{new_password};
	my $password = params->{new_password};
	return _error('confirm_password_missing') if not params->{password_confirm};
	return _errpr('password_mismatch') if $password ne params->{password_confirm};
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
		return _error('no_such_username')
			if not $user;
	} elsif ($email) {
		$user = $users_coll->find_one({ 'emails.email'  => $email });
		return _error('no_such_email')
			if not $user;
	} else {
		return _error('need_username_or_email');
	}
	return _error('user_does_not_have_email')
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
	_show_page(1);
};

get '/page/:n' => sub {
	my $page = params->{n};
	pass if $page  !~ /^\d+$/;
	redirect '/' if $page == 1;
	_show_page($page);
};

sub _show_page {
	my ($page) = @_;

	my $pages_coll = setting('db')->get_collection('pages');
	my $users_coll = setting('db')->get_collection('users');
	my $page_size = _site_config->{page_size};
	my $document_count = $pages_coll->find( { status => 'published' } )->count;

	pass if $page > 1 and $document_count <= ($page-1)*$page_size;

	my $pages = $pages_coll
			->find( { status => 'published' } )
			->sort( { created_timestamp => -1} )
			->skip( ($page-1)*$page_size )
			->limit( $page_size );
	my @pages;
	while (my $p = $pages->next) {
		$p->{id} = $p->{_id};
		my $user = $users_coll->find_one({ _id => $p->{author_id} });
		$p->{username}     = $user->{username};
		$p->{display_name} = $user->{display_name} || $user->{username};
		$p->{number_of_comments} = 0;
		push @pages, $p;
	 };
	template 'index', {
		pages     => \@pages,
		this_page => $page,
		prev_page => $page-1,
		next_page => ($document_count <= $page*$page_size ? 0 : $page+1),
	};
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
	return _error('site_exists') if _site_exists();

	my $site_title = params->{site_title};
	return _error('missing_site_title') if not $site_title;
	$site_title =~ s/^\s+|\s+$//g;
	return _error('invalid_site_title') if not $site_title;
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

	my %config = map { $_->{name} => $_->{default} } @site_configuration;
	my $config_coll = setting('db')->get_collection('config');
	$config_coll->insert({ name => 'site_config', %config });

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
		return _error('username_taken');
	}
	my $u2 = $users_coll->find_one({ 'emails.email' => $user_data->{emails}[0]{email} });
	if ($u2) {
		return _error('email_used');
	}

	my $user_id    = $users_coll->insert($user_data);
	Blog::Audit->save(
		user => $user_id,
		what => 'register',
		subject => '',
	);

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
	_error('missing_username') if not params->{username};
	_error('missing_password') if not params->{password};
	my %user = (
		username => params->{username},
		password => sha1_base64(params->{password}),
	);

	my $users_coll = setting('db')->get_collection('users');
	my $user_id    = $users_coll->find_one(\%user);
	return _error('could_not_authenticate') if not $user_id;

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

# TODO move this list in the database and serve the javascript
# with the same data
my %accept = map { $_ => 1 } qw(a i);
post '/u/comment' => sub {
	my $page_id = params->{page_id};
	#my $reply_to = params->{reply_to};
	my $comment = params->{comment_editor}; 
	return _error('no_comment_text') if not $comment;
	return _error('missing_post_id') if not $page_id;
	my $pages_coll = setting('db')->get_collection('pages');
	my $page  = $pages_coll->find_one({ _id => MongoDB::OID->new(value => $page_id) });
	return _error('no_such_page') if not $page;
	my @tags = $comment =~ /<(\w+)/g;
	foreach my $tag (@tags) {
		return _error('html_not_accepted', tag => $tag) if not $accept{$tag};
	}

	#$pages_coll->update({ _id => MongoDB::OID->new(value => $page_id) },
	#	{ '$push' => ); 
	return 'OK';
};


get '/u/create-post' => sub {
	my $id = params->{id};
	if ($id) {
		my $pages_coll = setting('db')->get_collection('pages');
		my $page  = $pages_coll->find_one({ _id => MongoDB::OID->new(value => $id) });
		_error('could_not_find_page_for_id', id => $id) if not $page;
		if ($page->{author_id} ne session('user_id')) {
			return _error('not_your_article');
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
		return _error('not_your_article') if $page->{author_id} ne $user_id;
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

	if (not $data{published_timestamp} and $data{status} eq 'published') {
		$data{published_timestamp} = DateTime->now;
	}

	# New post
	my $users_coll = setting('db')->get_collection('users');
	my $user = $users_coll->find_one({ _id => $user_id });
	return _error('could_not_find_user') if not $user;
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

get '/a/configuration' => sub {
	my $config_coll = setting('db')->get_collection('config');
	my $config = $config_coll->find_one({ name => 'site_config' });
	foreach my $c (@site_configuration) {
		$c->{value} = $config->{ $c->{name} } || $c->{default};
	}
	template 'site_configuration', { site_configuration => \@site_configuration };
};

post '/a/configuration' => sub {
	my $config_coll = setting('db')->get_collection('config');

	my %data;
	foreach my $c (@site_configuration) {
		my $value = params->{ $c->{name} };
		# TODO: validate!
		if ($c->{type} eq 'int') {
			if ($value !~ /^\d+$/) {
				return _error("invalid_value", field => $c->{display});
			}
		}
		$data{ $c->{name} } = $value;
	}
	my $ret = $config_coll->update({ name => 'site_config' }, { '$set' => \%data });
	if (not $ret->{updatedExisting}) {
		return _error('failed_to_update_configuration');
	}

	template 'message', { configuration_updated => 1 };
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
		return _error('no_password_confirm') if not params->{password_confirm};
		return _error('password_missmatch') if $password ne params->{password_confirm};
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
	return _error('not_implemented');
};

get qr{^/users/.*} => sub {
	my $path = request->path;
	my $pages_coll = setting('db')->get_collection('pages');
	my $page = $pages_coll->find_one( { permalink => $path } );
	pass if not $page;	

	my $users_coll = setting('db')->get_collection('users');
	my $user  = $users_coll->find_one({ _id => $page->{author_id} });
	$page->{username} = $user->{username};
	$page->{display_name} = $user->{display_name} || $user->{username};
	$page->{number_of_comments} = 0;
	$page->{id} = "$page->{_id}";

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

sub _error {
	my ($code, %args) = @_;
	template 'message', { $code => 1, %args };
}

sub _check_new_user {
	return _error('missing_username') if not params->{username};
	return _error('invalid_username') if params->{username} !~ /^\w+$/;
	return _error('missing_email') if not params->{email_address};
	my $supplied_email = lc params->{email_address};
	$supplied_email =~ s/^\s+|\s+$//g;
	my $email = Email::Valid->address($supplied_email);
	return _error('invalid_email') if not $email or $email ne $supplied_email;
	return _error('missing_password')
		if not params->{initial_password} or not params->{password_confirm};
	return _error('password_missmatch')
		if params->{initial_password} ne params->{password_confirm};

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

=head2 Articles

Each Article has:

  Title:
  Abstract (text) with HTML editor
  Body (text) with HTML editor
  Tags: A comma separated list of values
  Format: (how the body and extended texts are displayed to the reader)
    None
    Markdown
    Other ideas:
       Convert Line Breaks
       Markdown with SmartyPants
       Rich Text
       Textile 2



=head2 Listing posts

The main page lists the N most recent posts. N can be set by the administrator
and it defaults to 10. If there are more posts a link will be shown at the
bottom of the page to the next page   /page/2 and so on.



=cut

