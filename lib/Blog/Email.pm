package Blog::Email;
use Moo;

use Data::Dumper qw(Dumper);
use Email::Sender::Simple qw(sendmail);
use Email::Simple;
#use Email::Simple::Creator;

use Blog::DB;

has url => (is => 'ro', required => 1);

=pod

=head2 send_validation_code

  my $email = Blog::Email->new(url => 'http://example.com');
  $email->send_validation_code(
     email_validation_address => to@example.com
     email_validation_code    => 'some long string',
     id => 'user id',
  );

=cut

# send_validation_code($user_data);
sub send_validation_code {
	my ($self, %data) = @_;

	my $url = $self->url;
	#die Dumper \%data;

	my $from = _get_from() or return;

	my $body = <<"END_MSG";
Hi,

In order to verify your email address, please click on the following link:
$url/validate-email/$data{id}/$data{email}{verify_code}

END_MSG

	my $email = Email::Simple->create(
		header => [
			To    => qq{"$data{name}" <$data{email}{email}>}, 
			From  => $from,
			Subject => "Please validate your e-mail address",
		],
		body => $body,
	);
 
	return if $ENV{TEST_HOST};
	sendmail($email);
}

sub send_password_set_code {
	my ($self, %data) = @_;

	my $url = $self->url;

	my $from = _get_from() or return;

	my $body = <<"END_MSG";
Hi,

In order reset your password, please click on the following link:
$url/reset-password/$data{id}/$data{code}

END_MSG

	my $email = Email::Simple->create(
		header => [
			To    => qq{"$data{name}" <$data{email}{email}>}, 
			From  => '<gabor@perlmaven.com>',
			Subject => "To set your new password",
		],
		body => $body,
	);
 
	return if $ENV{TEST_HOST};
	sendmail($email);
}

sub _get_from {
	my $db = Blog::DB->instance->db;
	my $config_coll = $db->get_collection('config');
	my $config = $config_coll->find_one({ name => 'site_config' });
	return if not $config->{from_email};
	return qq{"$config->{from_name}" <$config->{from_email}>};
}



1;

