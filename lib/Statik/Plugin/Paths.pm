# Name: Statik::Plugin::Paths;
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Paths'

package Statik::Plugin::Paths;

use strict;
use parent qw(Statik::Plugin);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------

# Convert the set up updated post paths to the full set of updated relative
# paths for which new pages should be generated
sub paths {
  my ($self, %arg) = @_;

  # Check arguments
  my $updates = $arg{updates} 
    or die "Required argument 'updates' missing";

  my @updates = sort keys %$updates or return;
  printf "+ Generating page_paths for %d updated posts\n", scalar @updates
    if $self->options->{verbose};

  my @paths = ( '' );

  my %done = ( '' => 1 );
  for my $path (@updates) {
    my $current_path = '';
    my @path_elt = split m!/!, $path;
    while (my $path_elt = shift @path_elt) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
      push @paths, $current_path;
    }
  }

  return @paths;
}

1;

=head1 NAME

Statik::Plugin::Paths - statik plugin that takes the set of updated posts
and generates the set of relative paths for which we need to generate updated
pages

=head1 SYNOPSIS

No configuration items.

=head1 DESCRIPTION

Statik::Plugin::Paths is a statik plugin that takes the set of updated posts
and generates the set of relative paths for which we need to generate updated
pages e.g. if one post has been updated - /foo/bar/text.txt - then this plugin
will return the following set of update paths:

=over 4

=item '' - representing the root path

=item /foo

=item /foo/bar

=item /foo/bar/test.txt

=back

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

