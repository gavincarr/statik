# Name: Statik::Plugin::Paginate
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Paginate'

package Statik::Plugin::Paginate;

use strict;
use parent qw(Statik::Plugin);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------

sub paginate {
  my ($self, %arg) = @_;

  # Check arguments
  my $updates = $arg{updates} 
    or die "Required argument 'updates' missing";
  my $page_paths = $arg{page_paths} 
    or die "Required argument 'page_paths' missing";

  my @updates = sort keys %$updates or return;
  printf "+ Generating page_paths for %d updated posts\n", scalar @updates
    if $self->options->{verbose};

  push @$page_paths, '';

  my %done = ( '' => 1 );
  for my $path (@updates) {
    my $current_path = '';
    my @path_elt = split m!/!, $path;
    while (my $path_elt = shift @path_elt) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
      push @$page_paths, $current_path;
    }
  }
}

1;

=head1 NAME

Statik::Plugin::Paginate - statik plugin that ...

=head1 SYNOPSIS

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::Paginate]
    # What name should I use?
    name = value


=head1 DESCRIPTION

Statik::Plugin::Paginate is a statik plugin that ...

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

