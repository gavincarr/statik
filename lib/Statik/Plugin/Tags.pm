# Name: Statik::Plugin::Tags
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Tags'

package Statik::Plugin::Tags;

use strict;
use parent qw(Statik::Plugin);
use File::Copy qw(move);
use List::MoreUtils qw(uniq);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::Tags] section to 
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # Directory (in static_dir) to use as root for our tag indexes
    tag_root                => 'tags',
    # Header in which to look for our comma-separated list of tags
    tag_header              => 'Tags',
    # Filename in which to store cached tag collection (in state_dir)
    tag_cache_file          => 'tag_cache',
  };
}

# -------------------------------------------------------------------------
# Hooks

sub start {
  my $self = shift;

  # Load tag cache (except in 'force' mode)
  my $fn = File::Spec->catfile($self->config->{state_dir}, $self->{tag_cache_file});
  if (-f $fn and ! $self->options->{force}) {
    open my $fh, '<', $fn 
      or die "Cannot open tag cache '$fn' for reading: $!\n";
    local $/ = undef;
    my $cache_data = <$fh>;
    $self->{cache} = $self->json->decode($cache_data) if $cache_data;
  }

  $self->{cache} ||= {
    # map from full_path => $tag_string }
    entries_tags => {},
    # map from tag => { %hash_keyed_by_full_path },
    tag_map => {},
    # map from tag => $tag_count,
    tag_counts => {},
  };
}

# Add tag/<tag> entries to paths map
sub paths {
  my ($self, %arg) = @_;

  # Check arguments
  my $entries_list = $arg{entries_list}
    or die "Required argument 'entries_list' missing";
  my $entries_map = $arg{entries_map}
    or die "Required argument 'entries_map' missing";
  my $updates = $arg{updates} 
    or die "Required argument 'updates' missing";

  my @updates = sort keys %$updates or return;
  printf "+ Generating updated tag paths for %d updated posts\n",
    scalar @updates
      if $self->options->{verbose};

  # Update tag sets for all updated posts
  my $cache = $self->{cache};
  my $config = $self->config;
  my $posts = $self->posts;
  my %tags = ();
  for my $path (@updates) {
    # Load the post at $path
    my $post = $posts->fetch(path => $path);
    my $tag_header = $post->header($self->{tag_header}) or next;
    my $new_post = not exists $cache->{entries_tags}->{$path};
    my @old_tags = sort uniq split /\s*,\s*/, $cache->{entries_tags}->{$path}->{tags} if ! $new_post;
    my @new_tags = sort uniq split /\s*,\s*/, $tag_header;
    next unless @new_tags or @old_tags;
    (my $rel_path = $path) =~ s!^ $config->{post_dir} /!!x
      if $self->options->{verbose};

    $cache->{entries_tags}->{$path} = $tag_header;
    if ($new_post) {
      printf "++ %s not in tag cache, adding %d tags\n", $rel_path, scalar @new_tags
        if $self->options->{verbose} && ! $self->options->{force};
      for my $tag (@new_tags) {
        $tags{$tag}++;
        $cache->{tag_map}->{$tag} ||= {};
        $cache->{tag_map}->{$tag}->{$path} = 1;
        $cache->{tag_counts}->{$tag}++;
      }
    }
    else {
      # If not a new post, we need to diff the tag sets and sync any changes
      my @deleted;
      my %new_tags = map { $_ => 1 } @new_tags;
      for my $tag (@old_tags) {
        delete $new_tags{$tag}, next if $new_tags{$tag};
        # If $tag is in @old_tags, but not @new_tags, add to @deleted set
        push @deleted, $tag;
      }
      # Any tags left in %new_tags are new, add to @added set
      my @added = sort keys %new_tags;

      # Add and remove added/deleted tags from cache
      if (@added or @deleted) {
        for my $tag (@deleted) {
          $tags{$tag}++;
          print "+ '$tag' tag deleted from $rel_path - removing from tag cache\n"
            if $self->options->{verbose};
          delete $cache->{tag_map}->{$tag}->{$path};
          delete $cache->{tag_map}->{$tag} unless keys %{$cache->{tag_map}->{$tag}};
          $cache->{tag_counts}->{$tag}--;
          delete $cache->{tag_counts}->{$tag} if $cache->{tag_counts}->{$tag} == 0;
        }
        for my $tag (@added) {
          $tags{$tag}++;
          print "+ '$tag' tag added to $rel_path - adding to tag cache\n"
            if $self->options->{verbose};
          $cache->{tag_map}->{$tag} ||= {};
          $cache->{tag_map}->{$tag}->{$path} = 1;
          $cache->{tag_counts}->{$tag}++;
        }
      }
    }
  }
  printf "+ Tags affected by updates: %s\n", join(',', sort keys %tags) || '(none)'
    if $self->options->{verbose} && ! $self->options->{force};

  # Map paths to entries_list subsets
  my %paths = ();
  my $max_posts = $self->config->{max_posts};
  for my $tag (sort keys %tags) {
    $paths{"$self->{tag_root}/$tag"} = [];
    my $count = 0;
    for (@$entries_list) {
      if ($cache->{tag_map}->{$tag}->{$_}) {
        push @{$paths{"$self->{tag_root}/$tag"}}, $_;
        last if ++$count >= $max_posts;
      }
    }
  }

  return %paths;
}

sub end {
  my $self = shift;

  # Save tag cache
  my $fn1 = File::Spec->catfile($self->config->{state_dir}, "$self->{tag_cache_file}.tmp");
  my $fn2 = File::Spec->catfile($self->config->{state_dir}, $self->{tag_cache_file});
  open my $fh, '>', $fn1
    or die "Cannot open tag cache '$fn1' for writing: $!\n";
  print $fh $self->json->encode($self->{cache})
    or die "Cannot write to tag cache '$fn1': $!\n";
  close $fh
    or die "Cannot close tag cache '$fn1': $!\n";
  move $fn1, $fn2
    or die "Cannot rename tag cache '$fn1' to '$fn2': $!\n";
}

# -------------------------------------------------------------------------
# Public methods

# Expose configuration settings
sub tag_root   { $_[0]->{tag_root} }
sub tag_header { $_[0]->{tag_header} }

# Return an arrayref of tags for the given $post_path 
sub get_post_tags {
  my ($self, $post_path) = @_;

  $self->_croak("Missing 'post_path' argument") unless $post_path;
  my $tag_string = $self->{cache}->{entries_tags}->{$post_path} or return [];
  return [ split /\s*,\s*/, $tag_string ];
}

# Return the number of posts
sub get_tag_count {
  my ($self, $tag) = @_;
  $self->_croak("Missing 'tag' argument") unless $tag;
  return $self->{cache}->{tag_counts}->{$tag} || 0;
}

# Return a hashref of all tag => post counts mappings
sub get_tag_counts {
  my $self = shift;
  return $self->{cache}->{tag_counts};
}

1;

__END__

=head1 NAME

Statik::Plugin::Tags - tagging plugin for Statik

=head1 CONFIGURATION

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::Tags]
    # Directory (in static_dir) to use as root for our tag indexes
    tag_root = tags
    # Header in which to look for our comma-separated list of tags
    tag_header = Tags
    # Filename in which to store cached tag collection (in state_dir)
    tag_cache_file = tag_cache


=head1 DESCRIPTION

Statik::Plugin::Tags is a Statik plugin that generates tag-based index pages.
For each comma-separated tag found in the 'tag_header' post header, it
generates index pages with all posts including that tag (in standard entries
order).

Tag index pages are located in a separate tree in the static directory, using
the following naming convention:

  $static_dir/$tag_root/$tag/index.$flavour

tag_root defaults to 'tags', so posts tagged 'statik' would be in
$static_dir/tags/statik/index.$flavour, which would typically map to a
/tags/statik/ URL path.

=head1 METHODS

Statik::Plugin::Tags exposes number of public methods for use by other
plugins:

=over 4

=item tag_root

Returns the tag_root configuration setting for the plugin.

=item tag_header

Returns the tag_header configuration setting for the plugin.

=item get_post_tags($post_path)

Returns an arrayref of tags defined for the given post path.

=item get_tag_count($tag)

Returns the number of posts using the given tag.

=item get_tag_counts

Returns a hashref containing all tag => post_count mappings.

=back

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011-2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

