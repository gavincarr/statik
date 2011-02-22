# Statik Plugin: Statik::Plugin::Entries
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: See the bottom of this file or type: perldoc Statik::Plugin::Entries

package Statik::Plugin::Entries;

use parent qw(Statik::Plugin);

use strict;
use File::stat;
use File::Find;
use File::Copy qw(move);
use Time::Local;
use Time::Piece;
use JSON;

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
    post_timestamp_header     => '',
    # Post timestamp strptime(1) format (required if post_timestamp_header is set)
    post_timestamp_format     => '%Y-%m-%d %T',
  };
}

# -------------------------------------------------------------------------

# Entries hook - returns a hashref of post files => (canonical) mtime, and
# another hashref of post files that need to be updated
sub entries {
  my $self = shift;
  my $config = $self->config;

  $self->{update_flag} = 0;
  $self->{index_file} = "$config->{state_dir}/$self->{entries_index}";

  my $files = {};
  my $symlinks = {};
  my $max_mtime = 0;
  my $updates = {};

  # Read entries_index data
  if (-f $self->{index_file}) {
    if (open my $fh, $self->{index_file})  {
      my $index_data = eval { local $/ = undef; decode_json <$fh> };
      if ($@) {
        warn "[entries_default] loading entries index '$self->{entries_index}' failed: $@\n";
      }
      else {
        $files = $index_data->{files};
        $symlinks = $index_data->{symlinks};
        $max_mtime = $index_data->{max_mtime} || 0;
      }
    }
    # debug(1, sprintf("loaded %d files, %d symlinks from %s", scalar keys %$files, scalar keys %$symlinks, $self->{entries_index}));
  }
  else {
    warn "[entries_default] no entries index '$self->{entries_index}' found\n";
  }

  # Check posts_flag if set
  if ($self->{posts_flag}) {
    if (-e $self->{posts_flag}) {
      my $flag_mtime = stat($self->{posts_flag})->mtime;
      if ($flag_mtime <= $max_mtime) {
        # debug(1, "flag_mtime $flag_mtime <= max_mtime $max_mtime - no new posts, skipping checks");
        return ($files, {});
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
  for my $file (keys %$files) { 
    if ( ! -f $file || ( -l $file && ! -f readlink($file)) ) {
      $self->{updates_flag}++; 
      delete $files->{$file};
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
        (my $path_filename_ext = $File::Find::name) =~ s!^\Q$config->{post_dir}\E/!!;
        my $path = $1;
        my $filename = $2;
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
            $self->{updates_flag}++;
            # debug(2, "new file_symlinks entry $path_filename_ext, updates_flag now $self->{updates_flag}");
          }
        }

        # Else if a new post file, add to $files
        elsif (! exists $files->{$File::Find::name}) {
          $files->{$File::Find::name} = $mtime;
          $self->{updates_flag}++;
          $max_mtime = $mtime if $mtime > $max_mtime;
          # debug(2, "new file entry $path_filename_ext, updates_flag now $self->{updates_flag}");
        }

        # If the index for this file is out-of-date, add to updates list
        my $index_file = "$config->{static_dir}/$path/index.$config->{index_flavours}->[0]";
        if ($config->{force}
            or ! -f $index_file
            or stat($index_file)->mtime < $mtime) {
          # debug(3, "index_file $index_file out of date") unless $config->{force};
          $updates->{$path_filename_ext} = 1;
          $max_mtime = $mtime if $mtime > $max_mtime;
        }
      }
    }, $config->{post_dir}
  );

  # Add symlinks to $files with mtime of symlink target
  for (keys %$symlinks) {
    my $target = readlink $_ or next;
    # Note that we only support symlinks pointing to other posts
    $files->{$_} = $files->{$target} if exists $files->{$target};
  }

  # Store $files, $symlinks and $max_mtime in $self for later hooks
  $self->{files} = $files;
  $self->{symlinks} = $symlinks;
  $self->{max_mtime} = $max_mtime;

  return ($files, $updates);
}

# Post hook, for updating timestamps from post_timestamp_header values
sub post {
  my ($self, %arg) = @_;
  my $config = $self->config;
  my $stash = $arg{stash};

  my $timestamp;
  if ($self->{post_timestamp_header} and
      $timestamp = $stash->{"header_$self->{post_timestamp_header}"}) {
    if (my $format = $self->{post_timestamp_format}) {
      if (my $t = eval { Time::Piece->strptime($timestamp, $format) }) {

        my $fullpath = $stash->{post_fullpath};
        # debug(2, "Timestamp header for $fullpath: " . $t->strftime('%Y-%m-%d %T %z'));
        my $header_mtime = $t->epoch;
        my $cache_mtime = $self->{files}->{$fullpath};
        if (! $cache_mtime || $cache_mtime != $header_mtime) {
          # debug(1, "Updating cache from timestamp header: $fullpath => " . $t->strftime('%Y-%m-%d %T %z'));
          $self->{files}->{$fullpath} = $header_mtime;
          $self->{updates_flag}++;
        }
      }
      else {
        warn "post_timestamp_header '$self->{post_timestamp_header}: $timestamp' not in format '$format' - skipping\n";
      }
    }
    else {
      warn "post_timestamp_format not set - required if using post_timestamp_header\n";
    }
  }

  return 1;
}

# Save index data if we've made any updates
sub end {
  my $self = shift;

  # If updates, save back to index
  if ($self->{updates_flag}) {
    # debug(1, "$self->{updates_flag} update(s), saving data to $self->{entries_index}");
    if (open my $index, '>', "$self->{index_file}.tmp") {
      print $index to_json({ 
        files => $self->{files},
        symlinks => $self->{symlinks},
        max_mtime => $self->{max_mtime},
      }, { 
        utf8 => 1,
        pretty => 1
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

To configure, add some or all of the following to your statik.conf:

=head1 DESCRIPTION

Statik::Plugin::Entries is a statik plugin for capturing and preserving
the original creation timestamp on posts. It maintains an index file
(configurable, but 'entries_default.index' by default) of creation
timestamps for all posts, and returns a file hash with modification
times from that index.

=head1 BUGS AND LIMITATIONS

Statik::Plugin::Entries currently only supports symlinks to local
post files, not symlinks to arbitrary files outside your post_dir.

Statik::Plugin::Entries doesn't currently do any kind caching.

Please report bugs directly to the author.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011, Gavin Carr.

This plugin is licensed under the terms of the GNU General Public Licence,
v3, or at your option, any later version.

=cut

# vim:ft=perl
