# Statik class for reading and parsing Statik posts, with caching

package Statik::PostFactory;

use strict;
use Statik::Post;

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

  $self->{cache}->{$path} = Statik::Post->new(
    file        => $path,
    encoding    => $self->{encoding},
  );
}

1;

