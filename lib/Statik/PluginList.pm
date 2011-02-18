package Statik::PluginList;

use strict;
use Carp;

my @DEFAULT_PLUGIN_LIST = qw(
  entries_default
);

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  $self->{config} = delete $arg{config} 
    or croak "Required argument 'config' missing";
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  $self->{plugin_list} = $self->{config}->{plugin_list};
  $self->{plugin_path} = $self->{config}->{plugin_path};

  $self->_load_plugins;

  $self;
}

# Load plugins defined in $config->{plugin_list}
sub _load_plugins {
  my $self = shift;

  # Get list of plugins from plugin_list
  my @plugins = ();
  if (-f $self->{plugin_list}) {
    open my $fh, '<', $self->{plugin_list}
      or die "Cannot open plugin list: $!\n";
    while (<$fh>) {
      # Skip blank lines and comments
      next if m/^#/ || m/^\s*$/;

      # Trim entries
      s/^\s+//;
      s/\s*#.*$//;

      push @plugins, $_;
    }
  }

  else {
    warn "Plugin list '$self->{plugin_list}' not found - loading defaults\n";
    @plugins = @DEFAULT_PLUGIN_LIST;
  }

  # Load all plugins
  $self->{plugins} = [];
  unshift @INC, @{$self->{plugin_path}};
  for my $plugin (@plugins) {
    my $plugin_name = $plugin;
    # For Statik::Plugin::Foo style modules we need a string require
    if ($plugin_name =~ m/::/) {
      eval { eval "require $plugin_name" };
    }
    else {
      eval { require $plugin_name };
    }
    if ($@) {
      warn "Error finding or loading blosxom plugin '$plugin': $@";
      next;
    }

    push @{$self->{plugins}}, $plugin->new(config => $self->{config});
  }
  shift @INC foreach @{$self->{plugin_path}};
}

# Return list of plugins, optionally restricted to those with given $hook
sub plugins {
  my ($self, $hook) = @_;
  if ($hook) {
    return grep { $_->can($hook) } @{$self->{plugins}};
  }
  else {
    return @{$self->{plugins}};
  }
}

sub first {
  my $self = shift;
  my @p = $self->plugins(@_);
  return $p[0];
}

1;
