# Statik class for parsing posts into headers and bodies

package Statik::Post;

use strict;
use Carp;

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  $self->{file} = delete $arg{file} 
    or croak "Required argument 'file' missing";
  $self->{encoding} = delete $arg{encoding} 
    or croak "Required argument 'encoding' missing";
  croak "File '$self->{file}' not found" if ! -f $self->{file};
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  # Read post data
  open my $fh, '<', $self->{file}
    or die "Cannot open post '$self->{file}': $!\n";
  binmode $fh, ":encoding($self->{encoding})";
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

__END__

=head1 NAME

Statik::Post - Statik class for parsing post files

=head1 SYNOPSIS

  use Statik::Post;
  
  $post = Statik::Post->new(
    file        => $path_to_file,
    encoding    => 'utf8',
  );

  # Accessors
  $post->headers;           # returns a hash of post headers
  $post->header($name);     # returns the header with the given name
  $post->body;              # returns the post body

=head1 DESCRIPTION

Statik::Post - Statik class for parsing post files

=head1 SEE ALSO

Statik::PostFactory

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2012-2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

