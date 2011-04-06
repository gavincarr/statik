# Statik class for parsing, caching, and fetching statik posts
#
package Statik::Posts;

use strict;
use Statik::Parser;

sub new {
  my ($class, %arg) = @_;
  my $self = bless { cache => {} }, ref $class || $class;

  $self->{encoding} = delete $arg{encoding} 
    or die "Required argument 'encoding' missing";
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  $self;
}

# Fetch and parse the post file at $path
sub fetch {
  my ($self, %arg) = @_;
  my $path = $self->{path} = delete $arg{path} 
    or die "Required argument 'path' missing";
  
  return $self->{cache}->{$path} if $self->{cache}->{$path};

  $self->{cache}->{$path} = Statik::Parser->new(
    file        => $path,
    encoding    => $self->{encoding},
  );
}

1;

