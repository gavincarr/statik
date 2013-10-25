package Statik::Util;

use strict;
use warnings;
use Exporter::Lite;

our @EXPORT = qw();
our @EXPORT_OK = qw(clean_path);

# Non-empty statik paths always begin without a '/' and end with a '/',
# so that simple string concatenation (without '/' separators) works cleanly.
# If $arg{first} is set, however, include a leading '/'.
# Also handle URI objects properly.
sub clean_path {
  my ($path, %arg) = @_;

  my $uri;
  if (ref $path && $path->can('path')) {
    $uri = $path;
    $path = $path->path;
  }

  if (! defined $path or $path eq '' or $path eq '/') {
    return $arg{first} ? '/' : '';
  }

  $path =~ s!^/+!!;
  $path =~ s{ (?<!:) //+ }{/}xg;
  $path =~ s!/*$!/!;
  
  # If $arg{first} is set, include a leading '/'
  if ($arg{first}) {
    $path = "/$path" unless substr($path,0,1) eq '/';
  }

  if ($uri) {
    $uri->path($path);
    return $uri->canonical->as_string;
  }
  else {
    return $path;
  }
}

1;

=head1 NAME

Statik::Util - utility routines for Statik

=head1 SYNOPSIS

    use Statik::Util qw(clean_path);
  
    # Clean and return the given path. Non-empty paths in Statik always
    # begin without a '/' and end with a '/', so that simple string
    # concatenation works cleanly.
    $path = clean_path($path);
    # If 'first' is set, however, we include a leading '/' as well
    $path = clean_path('foo/bar', first => 1);      # => '/foo/bar/'

=head1 DESCRIPTION

Statik::Util provides various utility routines for Statik.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011-2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut
