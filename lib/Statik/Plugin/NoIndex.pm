# Name: Statik::Plugin::NoIndex
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::NoIndex'

package Statik::Plugin::NoIndex;

use strict;
use parent qw(Statik::Plugin);
use Data::Dump qw(dd pp dump);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::NoIndex] section to
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {};
}

# -------------------------------------------------------------------------
# Hooks (delete those you aren't required)

sub start {
  my $self = shift;
  my $noindex_file = File::Spec->catfile($self->config->{post_dir}, 'noindex');
  if (-f $noindex_file) {
    my $encoding = $self->config->{blog_encoding};
    open my $fh, "<:encoding($encoding)", $noindex_file
      or $self->_die("Open of noindex file $noindex_file failed: $!\n");
    my $post_dir = $self->config->{post_dir};
    $post_dir .= '/' if substr($post_dir, -1) ne '/';
    my @noindex = map { chomp $_; "$post_dir$_" } grep ! /^#/, <$fh>;
    close $fh;
    $self->{noindex} = { map { $_ => 1 } @noindex };
    print "+ noindex file: " . dump(\@noindex) . "\n";
  }
}

sub noindex {
  my $self = shift;
  my %arg = @_;
  my $noindex = $arg{noindex};
  my $entries = $arg{entries};

  for my $entry (keys %$entries) {
    $noindex->{$entry} = 1 if $self->{noindex}->{$entry};
  }
}

1;

=head1 NAME

Statik::Plugin::NoIndex - Statik plugin that omits specified posts from indexes

=head1 CONFIGURATION

No configuration items.

=head1 DESCRIPTION

Statik::Plugin::NoIndex is a Statik plugin that omits specified posts from indexes.

Posts to omit are specified in a 'noindex' file within your posts directory, and
are specified as literal paths relative to the post directory itself. Comments
(lines beginning with '#') are allowed. For example:

    # Content of posts/noindex
    # Omit 'About' page from indexes
    about.txt
    # Omit test posts
    test/test1.txt
    test/test2.txt
    test/test3.txt

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

