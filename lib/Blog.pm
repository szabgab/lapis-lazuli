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

if ($ENV{HARNESS_ACTIVE}) {
	set log  => "warning";
}

my @site_configuration = (
	{
		display => 'Site title',
		name    => 'site_title',
		type    => 'text',
		default => '',
	},
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
	{
		display => 'Accepted HTML tags',
		name    => 'accepted_html_tags',
		type    => 'text',
		default => 'a, b, i, ul, ol, li, img, br, p, pre',
	},
);

sub _site_config {
	my $config_coll = setting('db')->get_collection('config');
	my %defaults = map { $_->{name} => $_->{default} } @site_configuration;
	my $cfg = $config_coll->find_one({ _id => 'site_config' }) || {};
	my %config = (%defaults, %$cfg);
	return \%config;
}

sub _site_exists {
	my $config_coll = setting('db')->get_collection('config');
	my $cfg = $config_coll->find_one({ _id => 'site_config' }) || {};
	return $cfg && %$cfg ? 1 : 0;
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
		$t->{title} = _site_config->{site_title};
	}
	my $users_coll = setting('db')->get_collection('users');

	if (logged_in()) {
		my $user_id = session('user_id');
		my $user  = $users_coll->find_one({ _id => $user_id });
		$t->{user}{display_name} = $user->{display_name} || $user->{username};
		$t->{user}{admin} = $user->{admin};
	}

	unless (request->path =~ m{^/setup}) {
		$t->{show_sidebar} = 1;
	}
	$t->{accepted_html_tags} = to_json accepted_html_tags();
	$t->{query} = params->{query};

	if (request->path =~ m{^/users/([^/]+)}) {
		my $username = $1;
		my $user  = $users_coll->find_one({ username => $username });
		my $display_name = $user->{display_name};
		$t->{user_feed} = {
			username => $username,
			display_name => ($display_name || $username),
		}
	}
	return;
};

get '/robots.txt' => sub {
	# Sitemap: <% request.uri_base %>/sitemap.xml
	return 'Sitemap: ' . request->uri_base . '/sitemap.xml';
};

get '/atom.xml' => sub {
	my %query = (
		status => 'published',
	);
	atom_pages(\%query, '');
};

get '/comments.xml' => sub {
	my %query = (
		status => 'published',
	);
	atom_comments(\%query, '');
};

get '/sitemap.xml' => sub {
	my $pages_coll = setting('db')->get_collection('pages');
	my $pages = $pages_coll->find( { status => 'published' } );
	# TODO: add /page/N
	# TODO: add /tag/TAG

	my $url = request->base;
	$url =~ s{/$}{};
	content_type 'application/xml';

	my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n};
	$xml .= qq{<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};

	$xml .= qq{  <url>\n};
		$xml .= qq{    <loc>$url/</loc>\n};
		$xml .= sprintf qq{    <lastmod>%s</lastmod>\n}, DateTime->now->ymd;
	$xml .= qq{  </url>\n};

	while (my $p = $pages->next) {
		$xml .= qq{  <url>\n};
		$xml .= qq{    <loc>$url$p->{permalink}</loc>\n};
		if ($p->{updated_timestamp}) {
			# YYYY-MM-DD
			$xml .= sprintf qq{    <lastmod>%s</lastmod>\n}, substr($p->{updated_timestamp}, 0, 10);
		}
		#$xml .= qq{    <changefreq>monthly</changefreq>\n};
		#$xml .= qq{    <priority>0.8</priority>\n};
		$xml .= qq{  </url>\n};
	}
	$xml .= qq{</urlset>\n};
	return $xml;
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
	my %query = (
		status => 'published',
	);

	_list_pages(1, \%query);

};

get '/page/:n' => sub {
	my $this_page = params->{n};
	pass if $this_page  !~ /^\d+$/;
	redirect '/' if $this_page == 1;

	my %query = (
		status => 'published',
	);

	_list_pages($this_page, \%query);
};

get '/search' => sub {
	my $query = params->{query};
	my $this_page  = params->{page} || 1;
	# TODO check input

	my %query = (
		status => 'published', 
		'$or' => [
			{ abstract => { '$regex' => $query } },
			{ body => { '$regex' => $query } },
		],
	);

	_list_pages($this_page, \%query);
};

sub _list_pages {
	my ($this_page, $query) = @_;

	my $pages_coll = setting('db')->get_collection('pages');
	my $page_size = _site_config->{page_size};
	my $document_count = $pages_coll->find( $query )->count;

	pass if $this_page > 1 and $document_count <= ($this_page-1)*$page_size;

	my $pages = $pages_coll
		->find( $query )
		->sort( { created_timestamp => -1} )
		->skip( ($this_page-1)*$page_size )
		->limit( $page_size );


	my $users_coll = setting('db')->get_collection('users');
	my @pages;
	while (my $page = $pages->next) {
		$page->{id} = $page->{_id};
		my $user = $users_coll->find_one({ _id => $page->{author_id} });
		$page->{username}     = $user->{username};
		$page->{display_name} = $user->{display_name} || $user->{username};
		$page->{number_of_comments} = @{ $page->{comments} || [] };
		push @pages, $page;
	 };
	template 'index', {
		pages     => \@pages,
		this_page => $this_page,
		prev_page => $this_page-1,
		next_page => ($document_count <= $this_page*$page_size ? 0 : $this_page+1),
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

	return _error('site_exists') if _site_exists();

	my $site_title = params->{site_title};
	return _error('missing_site_title') if not $site_title;
	$site_title =~ s/^\s+|\s+$//g;
	return _error('invalid_site_title') if not $site_title;

	my $config_coll = setting('db')->get_collection('config');
	$config_coll->insert({ _id => 'site_config',  site_title => $site_title });
	$config_coll->insert({ _id => 'comment_id', seq => 0 });

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

sub get_current {
	my ($field) = @_;

	my $config_coll = setting('db')->get_collection('config');
	return $config_coll->find_one( { _id => $field } )->{seq};
}

sub get_next {
	my ($field) = @_;

	my $config_coll = setting('db')->get_collection('config');
	return $config_coll->find_and_modify( {
		query  => { _id => $field },
		update => { '$inc' => { seq => 1 } },
		new  => 1,
	} )->{seq}
}

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
	my $accept = accepted_html_tags();
	foreach my $tag (@tags) {
		return _error('html_not_accepted', tag => $tag) if not $accept->{$tag};
	}

	$pages_coll->update({ _id => MongoDB::OID->new(value => $page_id) },
		{
			'$push' => {
				comments => {
					id        => get_next('comment_id'),
					user      => session('user_id'),
					text      => $comment,
					timestamp => DateTime->now,
					# TODO: response__to => comment id
				}
			}
		}); 
	redirect $page->{permalink};
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
		return template 'editor', {
			page => $page,
		};
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

	$data{$_} = params->{$_} for qw(title basename abstract body status fromat);
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
	my $config = $config_coll->find_one({ _id => 'site_config' });
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
	my $ret = $config_coll->update({ _id => 'site_config' }, { '$set' => \%data });
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

get '/users' => sub {
	my $users_coll = setting('db')->get_collection('users');
	my $users = $users_coll->find();
	template 'list_users', { users => [$users->all] };
};

get '/users/:username/profile' => sub {
	my $username = params->{username};
	my $users_coll = setting('db')->get_collection('users');
	my $user  = $users_coll->find_one({ username => $username });
	pass if not $user;

	return template 'profile', { the_user => $user };
};

get '/users/:username/atom.xml' => sub {
	my $users_coll = setting('db')->get_collection('users');
	my $user  = $users_coll->find_one({ username => params->{username} });
	pass if not $user;

	my %query = (
		status    => 'published',
		author_id => $user->{_id},
	);
	atom_pages(\%query, ' of ' . ($user->{display_name} || $user->{username}));
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
	$page->{number_of_comments} = @{ $page->{comments} || [] };
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

	template 'list_users', {
		users => [map {$_->{id} = $_->{_id}; $_ } $all_users->all],
		admin_view => 1,
	};
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

# returns a hash reference
sub accepted_html_tags {
	return {
		map { $_ => 1 }
			split /\s*,\s*/, _site_config->{accepted_html_tags}
	};
}


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


sub logged_in {
	my $TIMEOUT = 24*60*60;

	return if not session('last_seen');
	return if session('last_seen') < time - $TIMEOUT;

	session last_seen => time;
	return 1;
}

sub atom_pages {
	my ($query, $subtitle) = @_;

	my $title = _site_config->{site_title};
	if ($subtitle) {
		$title .= $subtitle;
	}
	my $pages_coll = setting('db')->get_collection('pages');
	my $page_size = _site_config->{page_size};

	my $pages = $pages_coll
		->find( $query )
		->sort( { created_timestamp => -1} )
		->limit( $page_size );

	my $url = request->uri_base;
	$url =~ s{/$}{};

	my $users_coll = setting('db')->get_collection('users');
	my @pages;
	while (my $page = $pages->next) {
		#$page->{id} = $page->{_id};
		my $user = $users_coll->find_one({ _id => $page->{author_id} });
		#$page->{author}{username}     = $user->{username};
		$page->{author}{display_name} = $user->{display_name} || $user->{username};
		#$page->{number_of_comments} = @{ $page->{comments} || [] };
		$page->{permalink} = $url . $page->{permalink};
		push @pages, $page;
	 };

	content_type 'application/atom+xml';
	return template 'atom', {
		pages => \@pages,
		now   => DateTime->now,
		title => $title,
	},
	{ layout => 'none' };
}

# TODO
# fetching the most recent comments is not easy.
# fetching the most recent comments on the posts of a specific user is
# even more expensive.
# so the implementation has been delayed
# Maybe this is the right time to start keeping a "cache"
# path => { data structure }
# /users/foo/comments.xml => {}
# /comments.xml => {}
# when a comment is made we call a method that will update these data
# structures
# we might still need a process that will be able to build them from
# scratch.
sub atom_comments {
	my ($query, $subtitle) = @_;

	my $title = _site_config->{site_title};
	if ($subtitle) {
		$title .= $subtitle;
	}

	my $url = request->uri_base;
	$url =~ s{/$}{};

	my $comment_id = get_current('comment_id');
	my $page_size = _site_config->{page_size};

	my $pages_coll = setting('db')->get_collection('pages');
	my $users_coll = setting('db')->get_collection('users');

	my @pages;
	#my $pages = $pages_coll
	#	->find( $query )
	#	->sort( { created_timestamp => -1} )
	#	map { @{$_->{comments} $pages->{all}
	#
	#while (my $page = $pages->next) {
	#	#$page->{id} = $page->{_id};
	#	my $user = $users_coll->find_one({ _id => $page->{author_id} });
	#	#$page->{author}{username}     = $user->{username};
	#	$page->{author}{display_name} = $user->{display_name} || $user->{username};
	#	#$page->{number_of_comments} = @{ $page->{comments} || [] };
	#	$page->{permalink} = $url . $page->{permalink};
	#	push @pages, $page;
	# };

	content_type 'application/atom+xml';
	return template 'atom', {
		pages => \@pages,
		now   => DateTime->now,
		title => $title,
	},
	{ layout => 'none' };
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

=head2 Comments

Allow comments on the article specific pages.

Have a link "Comment" and for every existing comment have a link
"Reply". Once clicked, open a text editor and let the
user type some text (some HTML might be allowed).
Allow formatting (HTML/Markdown etc).

=head2 HTML tags

Limit the accepted HTML tags, check this limitation both in
JavaScript during the editing phase and then on submission.
Allow the administrator to set the accepted list of tags.
Default is: a, b, i, ul, ol, li

=head2 Listing posts

Layout of the reader pages:

The main page lists the N most recent posts showing only the "abstract" part.
N can be set by the administrator
and it defaults to 10. If there are more posts a link will be shown at the
bottom of the page to the next page   /page/2 and so on.

/page/1 is also available but it redirects to the main page


=head2 Permalink of each post is

/users/USER_NAME/YYYY/MM/BASENAME.html

It shows both the body and the extented part of the post
together with the tags and the comments.

#comments is the anchor to the top of the comments
Each comment has an achon #comment-COMMENTID
(the commentid is a number)

=head2 Search

Search: full textsearch on the posts and comments

Limit the search for the posts of a user and the
comments made on her posts.

=head2 Feeds

/atom.xml is the feed of the most recent entries
/comments.xml is the feed of the most recent comments

For pages of individual users (and posts by users), so basically
/users/USERNAME/atom.xml

=head2 Site Configuration

Configuration option that the Administrators can set

=over 4

=item Site Title

=item From Name

=item From Email

=item Page size

Number of entries shown when listing entries
(e.g. main page, page/N, search results etc.)

=item Accepted HTML tags

A list of HTML tags that will be accepted.

=item Enable Comments

Enable/Disable 

Let user override (Yes/No)

=back

=head2 User Preferences

=over 4

=item Comments

Enable/Disable (for all the posts of this user)

=back

=cut

