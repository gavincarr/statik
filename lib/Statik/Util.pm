package Statik::Util;

use strict;
use warnings;
use Exporter::Lite;

our @EXPORT = qw();
our @EXPORT_OK = qw(clean_path);

# Statik paths always begin without a '/' and end with a '/' (unless
# they're an empty string), so that simple string concatenation always
# works cleanly. 
sub clean_path {
  my $path = shift;
  return '' if $path eq '' or $path eq '/' or ! defined $path;
  $path =~ s!^/+!!;
  $path =~ s!/*$!/!;
  return $path;
}

1;

=head1 NAME

Statik::Util - utility routines for Statik

=head1 SYNOPSIS

    use Statik::Util qw(clean_path);
  
    # Clean and return the given path. Paths in Statik always begin without
    # a '/' and end with a '/' (unless they're an empty string), so that
    # simple string concatenation works cleanly.
    $path = clean_path($path);

=head1 DESCRIPTION

Statik::Util provides various utility routines for Statik.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

