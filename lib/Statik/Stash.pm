package Statik::Stash;

use strict;
use Carp;
use Statik::Util qw(clean_path);

# In xml_escape mode, we escape the fields here, and any set via 'set'
my @escape_fields = qw(blog_title blog_description url);
my %escape = (
  q(<) => '&lt;',
  q(>) => '&gt;',
  q(&) => '&amp;',
# q(') => '&apos;',
# q(") => '&quot;',
);
my $escape_re = join('|', keys %escape);

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, $class;

  # Check arguments
  my $config = delete $arg{config} 
    or croak "Required argument 'config' missing";
  $self->{flavour} = delete $arg{flavour} 
    or croak "Required argument 'flavour' missing";
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  # Initialise
  my $fconfig = $config->flavour($self->{flavour});
  $self->{suffix} = $fconfig->{suffix};
  $self->{_xml_escape} = $fconfig->{xml_escape};

  my %stash = $config->to_stash;
  @$self{ keys %stash } = values %stash;

  if ($self->{_xml_escape}) {
    $self->set($_ => $self->{$_}) foreach @escape_fields;
  }

  $self;
}

# Return the value for $key
sub get {
  my ($self, $key) = @_;
  $self->{key};
}

# Set the value for $key to $value. If xml escaping is turned on, $value
# is xml-escaped, and an additional key "${key}_unesc" is set to the 
# original unescaped value.
sub set {
  my ($self, $key, $value) = @_;
  if ($self->{_xml_escape} && defined $value) {
    $self->{"${key}_unesc"} = $value;
    $value =~ s/($escape_re)/$escape{$1}/g;
    $self->{$key} = $value;
  }
  else {
    $self->{$key} = $value;
    $self->{"${key}_unesc"} = $value;
  }
}

# Set the value of $key to $value (runs clean_path on value, no unescaping)
sub set_as_path {
  my ($self, $key, $value) = @_;
  $self->{$key} = clean_path($value);
}

# Set the value of $key to $value (must be epoch seconds or a Time::Piece
# object), and also derive and store various other date elements from it
sub set_as_date {
  my ($self, $key, $value) = @_;
  die "Invalid date value '$value' for '$key' - not seconds or Time::Piece object\n"
    unless $value =~ /^\d+$/ or (ref $value && $value->isa('Time::Piece'));

  my $t = ref $value ? $value : Time::Piece->strptime($value, '%s');

  if ($key) {
    $self->{$key} = $t;
    $key .= '_';
  }

  # Set some generally useful date elements
  $self->{${key} . "epoch"}         = $t->epoch;
  $self->{${key} . "date"}          = $t->date;               # %Y-%m-%d
  $self->{${key} . "time"}          = $t->time;               # %H:%M:%S
  $self->{${key} . "iso8601"}       = $t->strftime('%Y-%m-%dT%T%z');

  # Set blosxom-like date elements
  $self->{${key} . "yr"}            = $t->year;               # 2011
  $self->{${key} . "mo_num"}        = $t->strftime('%m');     # 02
  $self->{${key} . "mo"}            = $t->month;              # Feb
  $self->{${key} . "da"}            = $t->strftime('%d');     # 05
  $self->{${key} . "dw"}            = $t->day;                # Sat
  $self->{${key} . "ti"}            = $t->strftime('%H:%M');  # 13:32
  $self->{${key} . "hr"}            = $t->strftime('%H');     # 13
  $self->{${key} . "hr12"}          = $t->strftime('%H')%12;  # 1
  $self->{${key} . "min"}           = $t->strftime('%M');     # 32
  $self->{${key} . "ampm"}          = $t->strftime('%H') >= 12 ? 'pm' : 'am';
  $self->{${key} . "utc_offset"}    = $t->strftime('%z');     # +1100

  # And some useful extras
  $self->{${key} . "mday"}          = $t->mday;               # 5
  $self->{${key} . "fullmonth"}     = $t->fullmonth;          # February
  $self->{${key} . "fullday"}       = $t->fullday;            # Saturday

  # For blosxom-compatibility and simplicity, also set un-prefixed versions
  # of all post_created timestamps e.g. qw(dw da mo mo_num yr ti date time)
  if ($key eq 'post_created_') {
    $self->set_as_date('' => $t);
  }
}

# Delete $key from stash
sub delete {
  my ($self, $key) = @_;
  delete $self->{$key};
}

# Delete all keys matching $pattern from stash
sub delete_all {
  my ($self, $pattern) = @_;
  for (keys %$self) {
    delete $self->{$_} if m/$pattern/;
  }
  return $self;
}

1;

=head1 NAME

Statik::Stash - stash class used for passing statik variables through to templates

=head1 SYNOPSIS

  # Most statik plugin hooks are passed a reference to the stash, and
  # can add their own values to it (preferably namespaced) using set():
  $stash->set(myplugin_section => 5);
  $stash->set(myplugin_topic => 'Hello World!');

  # The set_as_date() method also exists, which expects an epoch seconds
  # or Time::Piece value, and adds an additional set of derived variables.
  # The following adds 'foo_started', 'foo_started_date', 'foo_started_time',
  # and many more. See L<set_as_date()> below for details.
  $stash->set_as_date(foo_started => localtime);

  # Keys can also be deleted individually, or as a group:
  $stash->delete($key);
  $stash->delete_all(qr/^myplugin_/);


  # Statik templates can then reference those variables directly using
  # $variable strings e.g. referencing the above values in a statik
  # template fragment:
  <div id="section">Section $myplugin_section</div>
  <h2>Topic: $myplugin_topic</h2>


=head1 DESCRIPTION

Statik::Stash is a simple blessed hashref used to pass statik variables
through to templates. It is instantiated by the statik core and is
associated with a particular flavour/theme and path.

A core set of stash variables are populated by statik itself. In
addition, the stash object is passed to most plugin hook subroutines,
allowing plugins to add their own (preferably namespaced) variables to
the stash, and/or modify existing ones.

Stash values are then used when interpolating into templates. The default
interpolator replaces occurrences of '$variable' with the value found in
$stash->{variable}.

For instance, a template fragement might read:

  <div id="section">Section $myplugin_section</div>
  <h2>Topic: $myplugin_topic</h2>

which might be interpolated into:

  <div id="section">Section 5</div>
  <h2>Topic: Hello World!</h2>


=head2 CORE STASH VARIABLES

Statik sets the following stash variables for all hooks after 'head':

=over 4

=item path

The path for the current collection or post, relative to the main
config post_dir, and without any filename.

Note that (relative) paths in Statik always begin without a '/', and end
with a '/' (unless they're an empty string), so that simple path
concatenation works cleanly.

=item is_index

Flag, set to 1 if this is an index page (as opposed to a post page).

=item page_num

For index pages, the number of this page (beginning at 1) in the current
collection.

=item page_total

For index pages, the total number of pages in the current collection.

=item index_updated

A datetime variable (see L<set_as_date> above) represending the mtime of the
newest post in the current collection.

=back

Statik sets the following stash variables for 'post' hooks:

=over 4

=item post_fullpath

The absolute filesystem path to the post text file, including file_extension.

=item post_path

The path component of post_fullpath relative to the main config post_dir, and
without the filename.

Note that (relative) paths in Statik always begin without a '/', and end
with a '/' (unless they're an empty string), so that simple path
concatenation works cleanly.

=item post_filename

post_fullpath basename (i.e. filename, without any path), without file_extension.

=item post_created

A datetime variable (see L<set_as_date> above) representing the nominal creation
datetime for this post (either as set explicitly via a header, or from the earliest
mtime seen by Statik for this post).

=item post_updated

A datetime variable (see L<set_as_date> above) representing the current mtime
of this post.

=item header_XXX

A set of post header variables, one per header. Header names are lowercased, so 
that the B<Title> header would be found in B<header_title>, the B<Date> header in 
B<header_date>, etc.

=item body

A string holding the current post body (xml-escaped as usual, if the xml-escape
flag is set for the current flavour. body_unesc also exists as usual, if you
want the raw unescaped version).

=item date_break

Boolean flag (0/1) indicating whether this is the first post on a new date i.e.
the current date has changed, and a date template may have generated new date
output.

=back


=head2 METHODS

=over 4

=item set(variable => value)

set is used to add new variables to the stash. If the flavour associated
with the stash has its B<xml_escape> flag set, then the value added to
the stash will be the xml-escaped version of the input parameter, and a
second variable called ${variable}_unesc is also added containing the
original unescaped version.

If the flavour's xml_escape flag is not set, $variable and ${variable}_unesc
keys are both still added to the stash, but their values will be identical.

=item set_as_path(variable => value)

set_as_path is a setter for paths - runs L<Statik::Util::clean_path> on
value (removing leading '/' characters, and adding a trailing '/'), and
skips unescaping.

=item set_as_date(variable => value)

set_as_date is an alternative setter specifically for datetimes, that
accepts only values that are epoch seconds or Time::Piece objects. It
stores the value in the stash as a Time::Piece object, and additionally
stores a whole series of derived entries, named with suffixes appended
to $variable. For instance, if variable was 'index_updated', the derived
entries would look like 'index_updated_epoch', 'index_updated_date',
'index_updated_iso8601', etc.

The core set of derived entries are:

=over 4

=item ${variable}_epoch

The datetime in epoch seconds.

=item ${variable}_date

=item ${variable}_time

=item ${variable}_iso8601

=item ${variable}_yr

=item ${variable}_mo_num

=item ${variable}_mo

=item ${variable}_da

=item ${variable}_dw

=item ${variable}_ti

=item ${variable}_hr

=item ${variable}_hr12

=item ${variable}_min

=item ${variable}_ampm

=item ${variable}_utc_offset

=item ${variable}_mday

=item ${variable}_fullmonth

=item ${variable}_fullday

=back

=item get(variable)

get is a trivial getter, included for completeness.

=item delete(key)

Delete the given key from stash.

=item delete_all(pattern)

Delete all keys matching the given pattern from the stash e.g.

  $stash->delete_all(qr/^myplugin_/);

=back


=head1 SEE ALSO

L<Statik>

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut
