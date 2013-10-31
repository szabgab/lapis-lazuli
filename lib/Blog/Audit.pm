package Blog::Audit;
use Moo;
use MooX::late;
#use Types::Standard;
use MooX::Types::MooseLike::Base qw(Enum);

use Blog::DB;

has user => (is => 'ro', required => 1); #, isa => 'MongoDB::OID'); # MongoID
has ts   => (is => 'ro', default => sub { time });
has what => (is => 'ro', required => 1,
	isa => Enum['register', 'delete', 'enabled', 'disabled']);
has subject => (is => 'ro', required => 1);

sub save {
	my ($class, @data) = @_;

	my $self = $class->new(@data);
	my $db = Blog::DB->instance->db;
	my $coll = $db->get_collection('audit');
	$coll->insert($self);
#{
#		user => $self->user,
#		ts   => $self->ts,
#		what => $self->what,
#		subject => $self->subject,
#	});
}


=head1 NAME

Blog::Audit - an audit trail of events

    {
      user => id,
      what => 'registered' / deleted / enabled / disabled / etc
      the subject => user_id | post_id | etc..
      ts => time,
    }

=cut

1;


