# Name: Statik::Plugin::PostTags
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::PostTags'

package Statik::Plugin::PostTags;

use strict;
use parent qw(Statik::Plugin);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::PostTags] section to
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {};
}

# -------------------------------------------------------------------------
# Hooks

sub start {
  my $self = shift;
  $self->{tags} = $self->find_plugin_which_can('get_post_tags')
    or $self->_die("Cannot find plugin providing get_post_tags() (Tags?)\n");
}

sub post {
  my ($self, %arg) = @_;
  my $stash = $arg{stash};

  my $taglist = $self->{tags}->get_post_tags( $stash->{post_fullpath} );
  my $tag_root = $self->{tags}->tag_root;

# $stash->{post_tags} = $taglist;
  $stash->{post_tag_string} = join(', ', @$taglist);
  $stash->{post_tag_links} = join(', ', map {
    qq(<a rel="tag" href="/$tag_root/$_" title="Posts tagged '$_'">$_</a>)
  } @$taglist);
}

1;

=head1 NAME

Statik::Plugin::PostTags - statik plugin for adding per-post tag items to the stash

=head1 CONFIGURATION

No configuration options.

=head1 DESCRIPTION

Statik::Plugin::PostTags is a statik plugin that adds per-post tag items to the
stash. The following items are added, and are therefore accessible as variables
in your templates:

=over 4

=item post_tag_string

A comma-separated list of tags for the post.

=item post_tag_links

A comma-separated list of tag links, in the form:

    <a rel="tag" href="/path/to/post" title="Posts tagged 'mytag'">mytag</a>

=head1 USAGE

This plugin requires the use of the Tags plugin (or another plugin supplying the
get_post_tags() method), and must occur after it in the plugins list.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

