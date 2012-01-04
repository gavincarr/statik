# Name: Statik::Plugin::Entries
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.002
# Documentation: See the bottom of this file or type: perldoc Statik::Plugin::Entries

package Statik::Plugin::Entries;

use parent qw(Statik::Plugin);

use strict;
use File::stat;
use File::Find;
use File::Copy qw(move);
use Time::Local;
use Time::Piece;
use Carp;

# Uncomment next line to enable debug output (don't uncomment debug() lines)
#use Blosxom::Debug debug_level => 2;

# -------------------------------------------------------------------------
# Configuration defaults. To change, add an [Statik::Plugin::Entries] section to 
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # What name should my index file be called?
    entries_index             => 'entries.index',
    # Whether to follow symlinks in posts directory
    follow_symlinks           => 0,
    # Optional flag file (or directory) updated on new/updated/deleted posts
    posts_flag                => '',
    # Post header to check for timestamp, overriding mtime if set
    post_timestamp_header     => 'Date',
    # Post timestamp strptime(1) format (required if post_timestamp_header is set)
    post_timestamp_format     => '%Y-%m-%d %T',
  };
}

# -------------------------------------------------------------------------

# Utility to produce a new hash of file => canonical mtime entries from the $posts hash
sub map_canonical_mtimes {
  my $self = shift;
  my $posts = shift;

  my $files = {};
  for (keys %$posts) {
    $files->{$_} = $posts->{$_}->{header_mtime} || $posts->{$_}->{create_mtime};
  }

  return $files;
}

# Entries hook - returns a hashref of post files => canonical mtime, and
# another hashref of post files that need to be updated
sub entries
{
  my $self = shift;
  my %arg = @_;

  my $config = $self->config;
  my $post_cache = $arg{posts}               # our Statik::Posts object
    or croak "Missing required 'posts' argument";

  $self->{update_flag} = 0;
  $self->{index_file} = "$config->{state_dir}/$self->{entries_index}"
    if $self->{entries_index} ne '';

  my $posts = {};
  my $symlinks = {};
  my $max_mtime = 0;
  my $updates = {};

  # Read entries_index data
  if ($self->{index_file} && -f $self->{index_file}) {
    if (open my $fh, $self->{index_file})  {
      my $index_data = eval { local $/ = undef; $self->json->decode(<$fh>) };
      if ($@) {
        warn "[entries_default] Warning: loading entries index '$self->{entries_index}' failed: $@\n";
      }
      else {
        $posts = $index_data->{posts};
        $symlinks = $index_data->{symlinks};
        $max_mtime = $index_data->{max_mtime} || 0;
      }
    }
    # debug(1, sprintf("loaded %d posts, %d symlinks from %s", scalar keys %$posts, scalar keys %$symlinks, $self->{entries_index}));
  }
  elsif ($self->{index_file}) {
    warn "[entries_default] Warning: no entries index '$self->{entries_index}' found\n";
  }

  # If posts_flag is set, we skip all processing unless posts_flag file has been touched
  if ($self->{posts_flag}) {
    if (-e $self->{posts_flag}) {
      my $flag_mtime = stat($self->{posts_flag})->mtime;
      if ($flag_mtime <= $max_mtime) {
        # debug(1, "flag_mtime $flag_mtime <= max_mtime $max_mtime - no new posts, skipping checks");
        return ($self->map_canonical_mtimes($posts), {});
      }
      else {
        # debug(1, "flag_mtime $flag_mtime > max_mtime $max_mtime - doing full check");
        $max_mtime = $flag_mtime;
        $self->{updates_flag}++; 
      }
    }
    else {
      warn "[entries_default] posts_flag '$self->{posts_flag}' not found!\n";
    }
  }

  # Check for deleted files
  for my $file (keys %$posts) { 
    if ( ! -f $file || ( -l $file && ! -f readlink($file)) ) {
      $updates->{$file} = 1;
      $self->{updates_flag}++; 
      delete $posts->{$file};
      delete $symlinks->{$file};
      # debug(2, "deleting removed file '$file' from updates");
    } 
  }

  # Check for new files
  find(
    {
      follow => $self->{follow_symlinks},
      wanted => sub {
        my $d; 
    
        # Return unless a match
        return unless $File::Find::name =~ 
          m! ^ \Q$config->{post_dir}\E / (?:(.*)/)? (.+) \. $config->{file_extension} $ !xo;
        my $path = $1 || '';
        my $filename = $2;
        (my $path_filename_ext = $File::Find::name) =~ s!^\Q$config->{post_dir}\E/!!;
        # Return if an index, a dotfile, or unreadable
        if ( $filename eq 'index' or $filename =~ /^\./ or ! -r $File::Find::name ) {
          # debug(1, "[entries_default] '$path_filename_ext' is an index, a dotfile, or is unreadable - skipping\n");
          return;
        }

        # Get modification time
        my $mtime = stat($File::Find::name)->mtime or return;

        # Ignore if future unless $show_future_entries is set
        return unless $config->{show_future_entries} or $mtime <= time;

        # If a new symlink, add to $symlinks
        if ( -l $File::Find::name ) {
          if (! exists $symlinks->{ $File::Find::name }) {
            $symlinks->{$File::Find::name} = 1;
            $updates->{$File::Find::name} = 1;
            $self->{updates_flag}++;
            # debug(2, "new file_symlinks entry $path_filename_ext, updates_flag now $self->{updates_flag}");
          }
        }

        # Else if a new post file, add to $posts
        elsif (! exists $posts->{$File::Find::name}) {
          $posts->{$File::Find::name} = { create_mtime => $mtime, current_mtime => $mtime };
          $updates->{$File::Find::name} = 1;
          $self->{updates_flag}++;
          $max_mtime = $mtime if $mtime > $max_mtime;
          # debug(2, "new file entry $path_filename_ext, updates_flag now $self->{updates_flag}");
        }

        # If an existing file, check if updated
        elsif ($mtime > $posts->{$File::Find::name}->{current_mtime}) {
          $posts->{$File::Find::name}->{current_mtime} = $mtime;
          $updates->{$File::Find::name} = 1;
          $self->{updates_flag}++;
          $max_mtime = $mtime if $mtime > $max_mtime;
        }

        # If --force is set, we add *all* files to the updates set
        elsif ($self->options->{force}) {
          $updates->{$File::Find::name} = 1;
          $self->{updates_flag}++;
        }
      }
    }, $config->{post_dir}
  );

  # Add symlinks to $posts with mtime of symlink target
  for (keys %$symlinks) {
    my $target = readlink $_ or next;
    # Note that we only support symlinks pointing to other posts
    $posts->{$_} = $posts->{$target} if exists $posts->{$target};
  }

  # Store $posts, $symlinks and $max_mtime in $self for later hooks
  $self->{posts} = $posts;
  $self->{symlinks} = $symlinks;
  $self->{max_mtime} = $max_mtime;

  # If post_timestamp_header is set, we need to re-extract header timestamps
  # from all updated posts.
  if (my $header = $self->{post_timestamp_header}) {
    for my $file (keys %$updates) {
      # Updates may be deletes
      -f $file or next;

      my $post = $post_cache->fetch( path => $file );
      my ($timestamp, $t);
      if ($timestamp = $post->{headers}->{$header} and
          $t = eval { Time::Piece->strptime($timestamp, $self->{post_timestamp_format}) } ) {
        # Record header_mtime as epoch of post_timestamp_header
        $self->{posts}->{$file}->{header_mtime} = $t->epoch;
      }
    }
  }

  return ($self->map_canonical_mtimes($posts), $updates);
}

# Save index data if we've made any updates
sub end {
  my $self = shift;

  # If updates, save back to index
  if ($self->{updates_flag} && $self->{index_file}) {
    # debug(1, "$self->{updates_flag} update(s), saving data to $self->{entries_index}");
    if (open my $index, '>', "$self->{index_file}.tmp") {
      print $index $self->json->encode({ 
        posts       => $self->{posts},
        symlinks    => $self->{symlinks},
        max_mtime   => $self->{max_mtime},
      }) and
      close $index and
      move("$self->{index_file}.tmp", $self->{index_file});
    }
    else {
      warn "[entries_default] couldn't open $self->{index_file}.tmp for writing: $!\n";
    }
  }
}

1;

__END__

=head1 NAME

Statik::Plugin::Entries: statik plugin to capture and preserve the original
creation timestamp on posts

=head1 SYNOPSIS

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::Entries]
    # What name should my index file be called?
    #entries_index             => 'entries.index',

    # Whether to follow symlinks in posts directory
    #follow_symlinks           => 0,

    # Optional flag file (or directory) updated by user on new/updated/deleted posts
    #posts_flag                => '',

    # Post header to check for timestamp, overriding mtime if set
    #post_timestamp_header     => 'Date',

    # Post timestamp strptime(1) format (required if post_timestamp_header is set)
    #post_timestamp_format     => '%Y-%m-%d %T',


=head1 DESCRIPTION

Statik::Plugin::Entries is a statik plugin for capturing and preserving
the original creation timestamp on posts, and (if post_timestamp_header
is set) for extracting header timestamps from posts. It maintains an
index file (configurable, but 'entries.index' by default) of these
timestamps for all posts, and returns a file hash with modification
times from that index.

=head1 BUGS AND LIMITATIONS

Statik::Plugin::Entries currently only supports symlinks to local
post files, not symlinks to arbitrary files outside your post_dir.

Please report bugs directly to the author.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011, Gavin Carr.

This plugin is licensed under the terms of the GNU General Public Licence,
v3, or at your option, any later version.

=cut

# vim:ft=perl
