
package Statik::Generator;

use strict;
use Carp;

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  for (qw(config plugins files)) {      # required
    $self->{$_} = delete $arg{$_} 
      or croak "Required argument '$_' missing";
  }
  for (qw(verbose noop)) {              # optional
    $self->{$_} = delete $arg{$_};
  }
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  $self;
}

# Generate updated post and index pages for the given post files
sub generate_updates {
  my ($self, %arg) = @_;

  # Check arguments
  my $updates = delete $arg{updates} 
    or croak "Required argument 'updates' missing";
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my @updates = sort keys %$updates or return;
  printf "+ Generating pages for %d updated posts\n", scalar @updates
    if $self->{verbose};

  $self->_generate_path('');

  my %done = ( '' => 1 );
  for my $path (@updates) {
    my $current_path = '';
    for my $path_elt (split m!/!, $path) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
      $self->_generate_path($current_path);
    }
  }
}

# Generate pages for the given path element (either a post or a directory)
sub _generate_path {
  my ($self, $path) = @_;
# print "+ generate_path: $path\n" if $self->{verbose};
  my $config = $self->{config};

  # Post file
  if ($path =~ m/\.$config->{file_extension}$/o) {
    for my $flavour (@{$config->{post_flavours}}) {
      (my $filename = $path) =~ s/\.$config->{file_extension}$/.$flavour/o;

      print "+ generating post output $filename\n" if $self->{verbose};
      my $output = $self->_generate_page(post => $path, flavour => $flavour);
    }
  }

  # Index
  else {
    mkdir "$config->{static_dir}/$path", 0755
      unless -d "$config->{static_dir}/$path" || $self->{noop};
    for my $flavour (@{$config->{index_flavours}}) {
      my $filename = $path ? "$path/index.$flavour" : "index.$flavour";

      print "+ generating index output $filename\n" if $self->{verbose};
      my $output = $self->_generate_page(path => $path, flavour => $flavour);
    }
  }
}

# Generate the output
sub _generate_page {
  my ($self, %arg) = @_;

  # Check arguments
  my $flavour = delete $arg{flavour} 
    or croak "Required argument 'flavour' missing";
  my $post = delete $arg{post};
  my $path = delete $arg{path};
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

}

1;
