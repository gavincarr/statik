package Statik::PluginList;

use strict;
use Carp;

my @DEFAULT_PLUGIN_LIST = qw(
  Statik::Plugin::Entries
  Statik::Plugin::Paths
  Statik::Plugin::Theme
);

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  $self->{config} = delete $arg{config}
    or croak "Required argument 'config' missing";
  $self->{options} = delete $arg{options}
    or croak "Required argument 'options' missing";
  $self->{posts} = delete $arg{posts}
    or croak "Required argument 'posts' missing";
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
  my %plugins = ();
  if (-f $self->{plugin_list}) {
    open my $fh, '<', $self->{plugin_list}
      or die "Cannot open plugin list: $!\n";
    while (<$fh>) {
      # Skip blank lines and comments
      next if m/^#/ || m/^\s*$/;

      # Trim entries
      chomp;
      s/^\s+//;
      s/\s*#.*$//;

      push @plugins, $_;
      $plugins{$_} = 1;
    }
  }
  else {
    warn "Plugin list '$self->{plugin_list}' not found - using defaults\n";
  }

  # Add default plugins if not already included
  push @plugins, grep { ! $plugins{$_} } @DEFAULT_PLUGIN_LIST;

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
      warn "Error finding or loading Statik plugin '$plugin': $@";
      next;
    }

    push @{$self->{plugins}}, $plugin->new(
      config        => $self->{config},
      options       => $self->{options},
      posts         => $self->{posts},
      plugin_list   => $self,
    );
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

# Return the first defined plugin with the given $hook
sub first {
  my ($self, $hook) = @_;

  my @p = $self->plugins($hook);
  return unless @p;

  return $p[0];
}

# Call the given hook routine with @args for all plugins until one returns results
sub call_first {
  my ($self, $hook, @args) = @_;

  for my $plugin ($self->plugins($hook)) {
    if (wantarray) {
      my @results = $plugin->$hook(@args);
      return @results if @results;
    }
    else {
      my $result = $plugin->$hook(@args);
      return $result if $result;
    }
  }
}

# Call all the given hook routines with @args for all plugins
sub call_all {
  my ($self, $hook, @args) = @_;

  my @return_values;
  for my $plugin ($self->plugins($hook)) {
    if (defined wantarray) {
      push @return_values, $plugin->$hook(@args);
    }
    else {
      $plugin->$hook(@args);
    }
  }

  return unless defined wantarray;
  return @return_values;
}

# Trivial convert-to-hash
sub TO_JSON {
  my $self = shift;
  return { %$self };
}

# Search the plugin list for the first which has the specified method
sub find_plugin_which_can {
  my ($self, $method) = @_;
  for my $plugin ($self->plugins) {
    return $plugin if $plugin->can($method);
  }
}

1;

=head1 NAME

Statik::PluginList - class holding the list of currently active statik plugins

=head1 SYNOPSIS

  use Statik::PluginList;
  
  # Load plugins using config plugin_list and plugin_path
  $plugins = Statik::PluginList->new(config => $config, options => $options);

  # Return full plugin list
  @plugins = $plugins->plugins;

  # Return the first defined plugin for the given hook
  $plugin = $plugins->first('entries');

  # Call the given hook with @args for all plugins until one returns results
  @results = $plugins->call_first('post', @args);
  $results = $plugins->call_first('sort', @args);

  # Call all the given hook routines with @args for all plugins
  $plugins->call_all('head', @args);


=head1 DESCRIPTION

Statik::PluginList is a class for loading and working with the list of currently
active statik plugins.

=head1 SEE ALSO

Statik

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

