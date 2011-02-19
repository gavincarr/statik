# Statik class for parsing posts into headers and bodies
#
package Statik::Parser;

use strict;
use Carp;

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  $self->{file} = delete $arg{file} 
    or croak "Required argument 'file' missing";
  croak "File '$self->{file}' not found" if ! -f $self->{file};
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  # Read post data
  open my $fh, '<', $self->{file}
    or die "Cannot open post '$self->{file}': $!\n";
  {
    local $/ = undef;
    $self->{raw} = <$fh>;
  }
  close $fh;

  # Parse data
  my ($headers, $body) = split m/\n\s*\n/s, $self->{raw}, 2;
  $headers =~ s/\n\s+/ /sg;
  $self->{headers} = {
    map { split /\s*:\s*/, $_, 2 } grep /:/, split(/\n/, $headers)
  };
  $self->{body} = $body;

  $self;
}

# Accessors

sub headers {
  my $self = shift;
  $self->{headers};
}

sub header {
  my ($self, $header) = @_;
  $self->{headers}->{$header};
}

sub body {
  my $self = shift;
  $self->{body};
}

1;

