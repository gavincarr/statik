package Statik;

use strict;
use YAML;
use Carp;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statik::Config;
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
  for (qw(force verbose noop)) {    # optional
    $self->{options}->{$_} = delete $arg{$_};
  }
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;
  $self->{options}->{verbose} ||= 0;

  # Load config file
  $self->{config} = Statik::Config->new(file => $self->{configfile});
  print Dump $self->{config} if $self->{verbose} >= 2;

  # Load plugins
  $self->{plugins} = Statik::PluginList->new(
    config  => $self->{config},
    options => $self->{options},
  );
  print Dump $self->{plugins} if $self->{verbose} >= 2;

  return $self;
}

sub generate {
  my $self = shift;
  my $config = $self->{config};
  my $options = $self->{options};
  my $plugins = $self->{plugins};

  # Hook: entries
  print "+ Loading entries from $config->{post_dir}\n" 
    if $self->{verbose};
  my ($files, $updates) = $plugins->call_first('entries', config => $config);
  printf "+ Found %d post files, %d updated\n",
    scalar keys %$files, scalar keys %$updates 
      if $self->{verbose};

  # Generate static pages
  my $gen = Statik::Generator->new(
    config      => $config,
    options     => $options,
    plugins     => $plugins,
    files       => $files,
  );
  $gen->generate_updates(updates => $updates);

  # Hook: end
  $plugins->call_all('end');

  $self;
}

1;
