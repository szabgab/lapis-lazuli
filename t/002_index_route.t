use Test::More tests => 1;
use strict;
use warnings;

# the order is important
use Blog;
use Dancer2::Test apps => ['Blog'];

ok 1;
#route_exists [GET => '/'], 'a route handler is defined for /';
#

# This depends on the status of the MongoDB, it sould be set for the test
#response_status_is ['GET' => '/'], 302, 'response status is 302 for /';
