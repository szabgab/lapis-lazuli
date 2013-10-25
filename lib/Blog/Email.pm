package Blog::Email;
use Moo;

use Data::Dumper qw(Dumper);

has url => (is => 'ro', required => 1);


use Email::Sender::Simple qw(sendmail);
use Email::Simple;
#use Email::Simple::Creator;

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
	my ($self, %user) = @_;

	my $url = $self->url;
	#die Dumper \%user;

	my $body = <<"END_MSG";
Hi,

In order to verify your email address, please click on the following link:
$url/validate-email/$user{id}/$user{email_validation_code}

END_MSG

	my $email = Email::Simple->create(
		header => [
			To    => $user{email_validation_address}, 
			From  => '<gabor@perlmaven.com>',
			Subject => "Please validate your e-mail address",
		],
		body => $body,
	);
 
	sendmail($email);
}


1;

