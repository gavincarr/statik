# Statik Plugin: Statik::Plugin::Atom
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Atom'

package Statik::Plugin::Atom;

use strict;
use parent qw(Statik::Plugin);
use URI;

# Uncomment next line to enable debug output (don't uncomment debug() lines)
#use Blosxom::Debug debug_level => 1;

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::Atom] section to 
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
  };
}

# -------------------------------------------------------------------------

sub start {
  my $self = shift;

  # Ensure $config->{blog_id_domain} is set
  if (! $self->config->{blog_id_domain}) {
    my $url = URI->new($self->config->{url})
      or die sprintf "Config url '%s' not a valid URL?\n", $self->config->{url};
    $self->config->{blog_id_domain} = $url->host;
  }
}

sub post {
  my ($self, %arg) = @_;
  my $stash = $arg{stash} or die "Missing stash argument";

  # Setup atom post items in stash
  # http://diveintomark.org/archives/2004/05/28/howto-atom-id
  $stash->{atom_entry_id} = sprintf 'tag:%s,%s:%s',
    $self->config->{blog_id_domain}, 
    $stash->{post_created_date},
    $stash->{post_path};
}

1;

__END__

=head1 NAME

Statik::Plugin::Atom - default statik atom plugin, adding atom-related
data to the statik stash for use by templates

=head1 SYNOPSIS

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::Atom]


=head1 DESCRIPTION

Statik::Plugin::Atom - default statik atom plugin, adding atom-related
data to the statik stash for use by templates.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011, Gavin Carr.

This plugin is licensed under the terms of the GNU General Public Licence,
v3, or at your option, any later version.

=cut

# vim:ft=perl

