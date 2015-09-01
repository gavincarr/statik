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
use DateTime::Format::Strptime;
use DateTime::Format::RFC3339;
use Carp;

use Statik::PostMutator;

# Uncomment next line to enable debug output (don't uncomment debug() lines)
#use Blosxom::Debug debug_level => 2;

# -------------------------------------------------------------------------
# Configuration defaults. To change, add an [Statik::Plugin::Entries] section to 
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # What name should my index file be called?
    entries_index                       => 'entries.index',
    # Whether to follow symlinks in posts directory
    follow_symlinks                     => 0,
    # Optional flag file used to tell us about new/updated/deleted posts
    posts_flag_file                     => '',
    # Post headers to explicitly set timestamps, overriding entries_index timestamps
    post_created_timestamp_header       => 'Date',
    post_modified_timestamp_header      => 'DateModified',
    # Update posts to add missing timestamp headers (requires write access to posts)
    # Note that setting this means you must maintain both post_created_timestamp_header
    # and post_modified_timestamp_header headers in all posts, since file mtime cannot be
    # trusted any more (it might be changed by us adding missing timestamp headers)
    post_add_missing_timestamp_headers  => 0,
    # Post timestamp strptime(1) format. Only required if you wish to set
    # post_created_timestamp_header or post_modified_timestamp_header headers by hand,
    # and are using a format other than RFC3339. If set, statik always tries both this
    # format and RFC3339, so you can use either or both. post_add_missing_timestamp_headers
    # headers are always added in RFC3339 format.
    post_timestamp_format               => '',
  };
}

# -------------------------------------------------------------------------

# Sanity check config
sub start {
  my $self = shift;

  $self->_die("post_add_missing_timestamp_headers option requires post_created_timestamp_header and post_modified_timestamp_header set\n")
    if $self->{post_add_missing_timestamp_headers} &&
      (! $self->{post_created_timestamp_header} ||
       ! $self->{post_modified_timestamp_header});

  $self->{strp} = DateTime::Format::Strptime->new( pattern => $self->{post_timestamp_format} )
    if $self->{post_timestamp_format};
  $self->{rfc3} = DateTime::Format::RFC3339->new;
}

# Produce a new hash of file path => post timestamps
sub _map_canonical_timestamps {
  my $self = shift;
  my $posts = shift;

  my $map = {};
  for (keys %$posts) {
    $map->{$_} ||= {};
    $map->{$_}->{create_ts} = $posts->{$_}->{header_created_ts} || $posts->{$_}->{create_mtime};
    $map->{$_}->{modify_ts} = $posts->{$_}->{header_modified_ts} || $posts->{$_}->{current_mtime};
  }

  return $map;
}

# Parse $timestamp string, trying both post_timestamp_format (if set), and RFC3339.
# Return a datetime object for the timestamp if successful, or undef if not.
sub _parse_header_timestamp {
  my ($self, $timestamp) = @_;

  my $dt;
  if ($self->{strp}) {
    $dt = $self->{strp}->parse_datetime($timestamp)
      or die "Incorrectly formatted timestamp '$timestamp' (not post_timestamp_format '$self->{post_timestamp_format}'";
  }
  else {
    $dt = eval { $self->{rfc3}->parse_datetime($timestamp) }
      or die "Incorrectly formatted timestamp '$timestamp' (not RFC3339)";
  }

  return $dt;
}

# Entries hook - returns one hashref of post files => canonical mtime,
# and a second hashref of post files that have been updated
sub entries
{
  my $self = shift;
  my %arg = @_;

  my $config = $self->config;
  my $post_factory = $arg{posts}               # our Statik::PostFactory object
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
    if (open my $fh, '<', $self->{index_file})  {
      my $index_data = eval { local $/ = undef; $self->json->decode(<$fh>) };
      if ($@) {
        $self->_die("Error: loading entries index '$self->{entries_index}' failed: $@\n");
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
    $self->_die("Error: no entries index '$self->{entries_index}' found\n");
  }

  # If posts_flag_file is set, we skip all processing unless posts_flag_file has been touched
  if ($self->{posts_flag_file}) {
    if (-e $self->{posts_flag_file}) {
      my $flag_mtime = stat($self->{posts_flag_file})->mtime;
      if ($flag_mtime <= $max_mtime) {
        # debug(1, "flag_mtime $flag_mtime <= max_mtime $max_mtime - no new posts, skipping checks");
        return ($self->_map_canonical_timestamps($posts), {});
      }
      else {
        # debug(1, "flag_mtime $flag_mtime > max_mtime $max_mtime - doing full check");
        $max_mtime = $flag_mtime;
        $self->{updates_flag}++; 
      }
    }
    else {
      $self->_warn("Warning: posts_flag_file '$self->{posts_flag_file}' not found!\n");
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
          # debug(1, "'$path_filename_ext' is an index, a dotfile, or is unreadable - skipping\n");
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

  # If post_created_timestamp_header is set, we need to re-extract header timestamps
  # from all updated posts, in case they've changed.
  if (my $created_ts_header = $self->{post_created_timestamp_header}) {
    for my $file (keys %$updates) {
      # Updates may be deletes
      -f $file or next;

      my $post = $post_factory->fetch( path => $file );
      my ($timestamp, $dt, $modified_ts_header);
      if ($timestamp = $post->{headers}->{$created_ts_header} and
          $dt = $self->_parse_header_timestamp($timestamp)) {
        # Record header_created_ts as epoch of post_created_timestamp_header
        $self->{posts}->{$file}->{header_created_ts} = $dt->epoch;
        if ($modified_ts_header = $self->{post_modified_timestamp_header} and
            $timestamp = $post->{headers}->{$modified_ts_header} and
            $dt = $self->_parse_header_timestamp($timestamp)) {
          # Record header_modified_ts as epoch of post_modified_timestamp_header
          $self->{posts}->{$file}->{header_modified_ts} = $dt->epoch;
        }
      }
      elsif ($self->{post_add_missing_timestamp_headers}) {
        $self->{missing_timestamp_headers} ||= {};
        $self->{missing_timestamp_headers}->{$file} = 1;
      }
    }
  }

  return ($self->_map_canonical_timestamps($posts), $updates);
}

# Save index data if we've made any updates
sub end {
  my $self = shift;

  # If updates, save back to index
  if ($self->{updates_flag} && $self->{index_file}) {
    # debug(1, "$self->{updates_flag} update(s), saving data to $self->{entries_index}");
    if (open my $index, '>', "$self->{index_file}.$$.tmp") {
      print $index $self->json->encode({ 
        posts       => $self->{posts},
        symlinks    => $self->{symlinks},
        max_mtime   => $self->{max_mtime},
      }) and
      close $index and
      move("$self->{index_file}.$$.tmp", $self->{index_file});
    }
    else {
      $self->_die("Couldn't open $self->{index_file}.$$.tmp for writing: $!\n");
    }
  }

  # If post_add_missing_timestamp_headers option is set, update posts missing timestamps
  if ($self->{post_add_missing_timestamp_headers} && $self->{missing_timestamp_headers}) {
    for my $file (keys %{ $self->{missing_timestamp_headers} }) {
      print "++ updating post $file with timestamp header\n"
        if $self->options->{verbose} >= 2;

      my $create_mtime = $self->{posts}->{$file}->{create_mtime};
      if (! $create_mtime) {
        warn "Cannot find create_mtime for post $file - skipping add of missing timestamp header\n";
        next;
      }
      my $modify_mtime = $self->{posts}->{$file}->{current_mtime};
      if (! $modify_mtime) {
        warn "Cannot find current_mtime for post $file - skipping add of missing timestamp header\n";
        next;
      }

      my $post = Statik::PostMutator->new(file => $file, encoding => $self->config->{blog_encoding});
      my $create_ts = DateTime->from_epoch( epoch => $create_mtime);
      my $modify_ts = DateTime->from_epoch( epoch => $modify_mtime);
      $post->add_header($self->{post_created_timestamp_header} => $self->{rfc3}->format_datetime($create_ts));
      $post->add_header($self->{post_modified_timestamp_header} => $self->{rfc3}->format_datetime($modify_ts));
      $post->write;
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
    #entries_index                          = entries.index

    # Whether to follow symlinks within posts directory
    #follow_symlinks                        = 0

    # Optional flag file (or directory) updated by user on new/updated/deleted posts
    #posts_flag_file                        =

    # Post headers to explicitly set timestamps, overriding entries_index timestamps
    #post_created_timestamp_header          = Date
    #post_modified_timestamp_header         = DateModified

    # Update posts to add missing timestamp headers (requires write access to posts)
    #post_add_missing_timestamp_headers     = 0

    # Post timestamp strptime(1) format. Only required if you wish to set
    # post_created_timestamp_header or post_modified_timestamp_header headers by hand,
    # and are using a format other than RFC3339. If set, statik always tries both this
    # format and RFC3339, so you can use either or both. post_add_missing_timestamp_headers
    # headers are always added in RFC3339 format.
    #post_timestamp_format                  =

=head1 DESCRIPTION

Statik::Plugin::Entries is a statik plugin for capturing and preserving
the original creation timestamp on posts, and (if
post_created_timestamp_header is set) for extracting header timestamps
from posts. It maintains an index file (configurable, but
'entries.index' by default) of these timestamps for all posts, and
returns a file hash with modification times from that index.

=head1 BUGS AND LIMITATIONS

Statik::Plugin::Entries currently only supports symlinks to local
post files, not symlinks to arbitrary files outside your post_dir.

Please report bugs directly to the author.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 LICENCE

Copyright 2011-2013 Gavin Carr.

This plugin is licensed under the terms of the GNU General Public Licence,
v3, or at your option, any later version.

=cut

# vim:ft=perl
