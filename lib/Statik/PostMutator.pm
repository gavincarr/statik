# Statik class for making updates to post files

package Statik::PostMutator;

use strict;
use parent 'Statik::Post';
use File::stat;
use File::Copy qw(move);
use Carp;

# Add a new header to post
sub add_header {
  my ($self, $header, $value) = @_;

  croak "Cannot add_header $header - already exists"
    if exists $self->headers->{$header};

  $self->headers->{$header} = $value;
  $self->{_dirty}++;
}

# Serialise
sub to_string {
  my $self = shift;

  my $string = '';
  while (my ($header, $value) = each %{ $self->{headers} }) {
    $string .= "$header: $value\n";
  }
  $string .= "\n";
  $string .= $self->body;

  return $string;
}

# Write modified post to disk, carefully
sub write {
  my $self = shift;

  if (! $self->{_dirty}) {
    carp "Post not modified - stubbornly refusing to write\n";
    return;
  }

  # Write modified content to tmpfile
  my $tmpfile = "$self->{file}.$$.tmp";
  open my $fh, ">:encoding($self->{encoding})", $tmpfile
    or croak "Opening tmpfile '$tmpfile' for write failed: $!";
  print $fh $self->to_string
    or croak "Printing to tmpfile '$tmpfile' failed: $!";
  close $fh
    or croak "Closing tmpfile '$tmpfile' failed: $!";

  # If we've only appended, tmpfile should be larger than original
  my $stat_old = stat $self->{file};
  my $stat_new = stat $tmpfile;
  if ($stat_new->size < $stat_old->size) {
    die sprintf "Size mismatch: tmpfile '%s' size %d is smaller than original '%s' size %s - aborting replace\n",
      $tmpfile, $stat_new->size, $self->{file}, $stat_old->size;
  }

  # Replace $self->{file} with $tmpfile
  move $tmpfile, $self->{file}
    or croak "Move of $tmpfile to $self->{file} failed: $!";
}

1;

