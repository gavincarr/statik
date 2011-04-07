# Name: Statik::Plugin::Tags
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Tags'

package Statik::Plugin::Tags;

use strict;
use parent qw(Statik::Plugin);
use File::Copy qw(move);

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::Tags] section to 
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # Header in which to look for our comma-separated list of tags
    tag_header              => 'Tags',
    # Filename in which to store cached tag collection (in state_dir)
    tag_cache_file          => 'tag_cache',
  };
}

# -------------------------------------------------------------------------

sub start {
  my $self = shift;

  # Load tag cache
  my $fn = File::Spec->catfile($self->config->{state_dir}, $self->{tag_cache_file});
  if (-f $fn) {
    open my $fh, '<', $fn 
      or die "Cannot open tag cache '$fn' for reading: $!\n";
    local $/ = undef;
    my $cache_data = <$fh>;
    $self->{cache} = $self->json->decode($cache_data) if $cache_data;
  }

  $self->{cache} ||= {
    # map from full_path => { mtime => $mtime, tags => $tag_string }
    entries_map => {},
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
  my $posts = $self->posts;
  my %tags = ();
  for my $path (@updates) {
    # Load the post at $path
    my $post = $posts->fetch(path => $path);
    my $tag_header = $post->header($self->{tag_header}) or next;
    my $new_post = not exists $cache->{entries_map}->{$path};
    my @old_tags = split /\s*,\s*/, $cache->{entries_map}->{$path}->{tags} if ! $new_post;
    $cache->{entries_map}->{$path} = { mtime => $updates->{$path}, tags => $tag_header };
    for my $tag (split /\s*,\s*/, $tag_header) {
      $tags{$tag}++;

      if ($new_post) {
        $cache->{tag_map}->{$tag} ||= {};
        $cache->{tag_map}->{$tag}->{$path} = 1;
        $cache->{tag_counts}->{$tag}++;
      }
      else {
        # TODO: if not a new post, we should diff the tag sets and sync any changes
      }
    }
  }
  printf "Tags affected by updates: %s\n", join(',', sort keys %tags);

  # Map paths to entries_list subsets
  my %paths = ();
  for my $tag (sort keys %tags) {
    $paths{"tag/$tag"} = [ grep { $cache->{tag_map}->{$tag}->{$_} } @$entries_list ];
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

1;

