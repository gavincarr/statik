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

# Convert the set of updated posts to a hashref whose keys are the set of
# relative paths for which we need to generate updated pages, and whose
# values are an arrayref holding the ordered list of fully-qualified post
# paths included within the given key.
sub paths {
  my ($self, %arg) = @_;

  # Check arguments
  my $entries_list = $arg{entries_list}
    or die "Required argument 'entries_list' missing";
  my $updates = $arg{updates} 
    or die "Required argument 'updates' missing";

  my @updates = sort keys %$updates or return;
  printf "+ Generating paths and posts sets for %d updated posts\n",
    scalar @updates
      if $self->options->{verbose};

  # Collect constituent path segments from updated paths
  my $post_dir = $self->config->{post_dir};
  my $rendering_posts = @{$self->config->{post_flavours}} > 0;
  my @paths = ( '' );
  my %paths = ();
  my %done = ( '' => 1 );
  for my $path (@updates) {
    $path =~ s{^ $post_dir / }{}x;
    my $current_path = '';
    my @path_elt = split m!/!, $path;
    while (my $path_elt = shift @path_elt) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
      # Add $current_path to paths if index, or we're rendering posts
      if (@path_elt) {
        push @paths, $current_path;
      }
      elsif ($rendering_posts) {
        push @paths, $current_path;
        $paths{$current_path} = $current_path;
      }
    }
  }

  # Map paths to entries_list subsets
  printf "+ Mapping %d paths to entries list subsets\n", scalar @paths
    if $self->options->{verbose};
  my $max_posts = $self->config->{max_posts};
  for my $path (@paths) {
    if ($path eq '') {
      $paths{$path} = [ @$entries_list ];
    }
    elsif (! $paths{$path}) {
      $paths{$path} = [];
      my $count = 0;
      for (@$entries_list) {
        if (m{^$post_dir/$path\b}) {
          push @{$paths{$path}}, $_;
          last if ++$count >= $max_posts;
        }
      }
    }
  }
  print "+ Path mapping complete\n"
    if $self->options->{verbose};

  return %paths;
}

1;

=head1 NAME

Statik::Plugin::Paths - statik plugin that takes the set of updated posts
and generates a hashref mapping relative path segments to fully qualified
post paths

=head1 SYNOPSIS

No configuration items.

=head1 DESCRIPTION

Statik::Plugin::Paths is a statik plugin that takes the set of updated posts
and generates a hashref whose keys are the set of relative paths for
which we need to generate updated pages, and whose values are an
arrayref holding the ordered list of fully-qualified post paths included
within the given key.

For example, if one post has been updated - /foo/bar/post.txt - then the
following hashref would be returned:

    {
        '':                 [ '/path/to/post/dir/foo/bar/post.txt' ],
        'foo':              [ '/path/to/post/dir/foo/bar/post.txt' ],
        'foo/bar':          [ '/path/to/post/dir/foo/bar/post.txt' ],
        'foo/bar/post.txt': [ '/path/to/post/dir/foo/bar/post.txt' ],
    }

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

