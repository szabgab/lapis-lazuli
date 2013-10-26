use strict;
use warnings;

# experimental code

use FindBin;
use lib "$FindBin::Bin/../lib";

use Blog::Email;
my $email = Blog::Email->new(url => 'http://example.com');

$email->send_validation_code(
	email => {
		email => 'szabgab@gmail.com',
		verify_code    => 'somelongstring',
	},
	id => '1234',
	name => 'Foo Bar',
  );



