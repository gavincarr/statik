# Base class for statik plugins

package Statik::Plugin;

use strict;
use JSON;
use Hash::Merge qw(merge);

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  $self->{_config} = delete $arg{config}
    or die "Required argument 'config' missing";
  $self->{_options} = delete $arg{options}
    or die "Required argument 'options' missing";
  $self->{_posts} = delete $arg{posts}
    or die "Required argument 'posts' missing";
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  # Initialise
  $self->{_json} = JSON->new->utf8->allow_blessed->convert_blessed->pretty;
  $self->{name} = ref $self;
  my $plugin_config = merge( $self->{_config}->{_config}->{$self->{name}}||{}, 
                             $self->defaults );
  for (qw(name)) {
    die "Can't use reserved attribute '$_' as $self->{name} config item"
      if exists $plugin_config->{$_};
  }
  $self->{$_} = $plugin_config->{$_} foreach keys %$plugin_config;

  # Call start() if exists
  $self->start if $self->can('start');

  $self;
}

# Plugin config defaults
sub defaults {
  return {};
}

sub config {
  my $self = shift;
  return $self->{_config};
}

sub options {
  my $self = shift;
  return $self->{_options};
}

sub posts {
  my $self = shift;
  return $self->{_posts};
}

sub json {
  my $self = shift;
  return $self->{_json};
}

1;

=head1 NAME

Statik::Plugin - base class for statik plugins

=head1 SYNOPSIS

  # Example plugin
  package Statik::Plugin::Sample;

  use strict;
  use parent qw(Statik::Plugin);

  # Plugins should provide a 'defaults' sub if they wish to provide any
  # plugin settings that can be configured in a [Statik::Plugin::Name]
  # section in the main statik.conf.
  sub defaults {
    return {
      name      => 'value',
    };
  }

  # Plugin hook methods
  sub start { ... }
  sub post  { ... }
  sub end   { ... }

  1;


=head1 DESCRIPTION

Statik::Plugin is the base class for statik plugins, providing a base
constructor and various utility methods to plugins.

=head2 CONSTRUCTOR

The base constructor handles setting up config settings either from the
defaults hash returned by the plugin defaults subroutine, or from any
plugin section in the statik.conf file (overriding the defaults). Plugin
config variables are made available as top-level attributes in the plugin
object i.e. if you define a config item of 'name', it will be defined and
available as $self->{name} to the plugin.

=head2 UTILITY METHODS

Statik::Plugin defines a number of utility methods for plugins:

=over 4

=item config()

Returns the top-level Statik::Config object with the settings defined
in the main statik.conf config file.

=item options()

Returns a hashref containing any runtime options in force for this statik
run. The options which may currently be defined here include 'verbose',
'noop', and 'force'.

=item posts()

Returns a Statik::Posts object which can be used to fetch and parse
individual posts e.g.

    my $post = $self->posts->fetch( $post_fullpath );

=item json()

Returns a JSON object which can be used for serialising data structures
to json e.g.

    print $self->json->encode $data;

=back

=head2 HOOK METHODS

Plugins can define hook methods which are called at various stages of
processing by the main statik library and generator. The set of hooks
which can be defined, and their expected arguments, are defined below.

All hooks are passed the $self object, and then a set of name => value
pairs as arguments, so that a typical hook subroutine might look like
this:

    sub post {
        my ($self, %args) = @_;
        my $stash = $args{stash};
        # Hook implementation
    }

=over 4

=item start

=item head

=item post

=item foot

=item end

=back

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

