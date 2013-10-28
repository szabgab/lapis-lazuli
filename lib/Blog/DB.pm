package Blog::DB;
use Moo;
with 'MooX::Singleton';

use MongoDB ();
has db => (is => 'lazy');
has host => (is => 'ro', required => 1);
has database => (is => 'ro', required => 1);

sub _build_db {
	my ($self) = @_;

	my $client = MongoDB::MongoClient->new(host => $self->host);
	return $client->get_database( $self->database );
}	


1;

