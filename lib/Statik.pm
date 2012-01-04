package Statik;

use strict;
use JSON;
use Carp;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statik::Config;
use Statik::Posts;
use Statik::PluginList;
use Statik::Generator;

our $VERSION = 0.01;

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, $class;

  # Check arguments
  $self->{configfile} = delete $arg{config} 
      or croak "Required argument 'config' missing";
  $self->{options} = {};
  for (qw(force verbose noop path)) {    # optional
    $self->{options}->{$_} = delete $arg{$_};
  }
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;
  $self->{options}->{verbose} ||= 0;
  $self->{json} = JSON->new->utf8->allow_blessed->convert_blessed->pretty
    if $self->{options}->{verbose};

  # Load config file
  $self->{config} = Statik::Config->new(file => $self->{configfile});
  print $self->{json}->encode($self->{config})
    if $self->{options}->{verbose} >= 2;

  # Setup posts cache
  $self->{posts} = Statik::Posts->new(encoding => $self->{config}->{blog_encoding});

  # Load plugins
  $self->{plugins} = Statik::PluginList->new(
    config  => $self->{config},
    options => $self->{options},
    posts   => $self->{posts},
  );
  print $self->{json}->encode($self->{plugins})
    if $self->{options}->{verbose} >= 2;

  return $self;
}

sub generate {
  my $self = shift;
  my $config = $self->{config};
  my $plugins = $self->{plugins};

  # Hook: entries
  print "+ Loading entries from $config->{post_dir}\n" 
    if $self->{options}->{verbose};
  my ($entries, $updates) = $plugins->call_first('entries', config => $config);
  printf "+ Found %d post files, %d updated\n",
    scalar keys %$entries, scalar keys %$updates 
      if $self->{options}->{verbose};

  # Hook: filter
  $plugins->call_all('filter', entries => $entries, updates => $updates);

  # Hook: sort
  # TODO: hookify
  my $sort_sub = sub {
    my ($entries) = @_;
    return sort { $entries->{$b} <=> $entries->{$a} } keys %$entries;
  };
  my @entries_list = $sort_sub->( $entries );

  # Hook: paths
  my %generate_paths = $plugins->call_all('paths',
    entries_list => \@entries_list,
    entries_map => $entries,
    updates => $updates,
  );
  if (defined $self->{options}->{path} and %generate_paths) {
    my %extracted = ();
    for (@{ $self->{options}->{path} }) {
      $_ = '' if $_ eq '/';
      $extracted{$_} = $generate_paths{$_};
    }
    %generate_paths = %extracted;
    printf "+ Paths pruned, %d entries remaining\n", scalar keys %generate_paths
      if $self->{options}->{verbose};
  }
  print $self->{json}->encode(\%generate_paths)
    if $self->{options}->{verbose} >= 3 and %generate_paths;

  # Generate static pages
  my $gen = Statik::Generator->new(
    config          => $config,
    options         => $self->{options},
    posts           => $self->{posts},
    plugins         => $plugins,
    entries_map     => $entries,
    entries_list    => \@entries_list,
    generate_paths  => \%generate_paths,
  );
  $gen->generate;

  # Hook: end
  $plugins->call_all('end');

  $self;
}

1;
