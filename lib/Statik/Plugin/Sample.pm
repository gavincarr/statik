# Name: Statik::Plugin::Sample
# Author(s): First Last <first.last@example.com>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Sample'

package Statik::Plugin::Sample;

use strict;
use parent qw(Statik::Plugin);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::Sample] section to
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # Some setting that does something or other
    name        => 'value',
  };
}

# -------------------------------------------------------------------------
# Hooks (delete those you aren't required)

sub start {
  my $self = shift;
}

1;

=head1 NAME

Statik::Plugin::Sample - statik plugin that ...

=head1 SYNOPSIS

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::Sample]
    # What name should I use?
    name = value


=head1 DESCRIPTION

Statik::Plugin::Sample is a statik plugin that ...

=head1 AUTHOR

First Last <first.last@example.com>

=head1 COPYRIGHT AND LICENCE

Copyright (C) First Last 2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

