package Statik;

use strict;
use JSON;
use Carp;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statik::Config;
use Statik::PostFactory;
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

  # Setup post factory
  $self->{posts} = Statik::PostFactory->new(encoding => $self->{config}->{blog_encoding});

  # Load plugins
  $self->{plugins} = Statik::PluginList->new(
    config  => $self->{config},
    options => $self->{options},
    posts   => $self->{posts},
  );
  print "++ plugins object: " . $self->{json}->encode($self->{plugins})
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
  my ($entries, $updates) = $plugins->call_first('entries',
    config => $config, posts => $self->{posts});
  printf "+ Found %d post files, %d updated\n",
    scalar keys %$entries, scalar keys %$updates
      if $self->{options}->{verbose};

  # Hook: filter
  $plugins->call_all('filter', entries => $entries, updates => $updates);

  # Hook: noindex (experimental)
  my %noindex;
  $plugins->call_all('noindex', noindex => \%noindex, entries => $entries, updates => $updates);
  print "++ noindex: " . $self->{json}->encode(\%noindex)
    if $self->{options}->{verbose} >= 2;

  # Hook: sort
  # TODO: hookify
  my $sort_sub = sub {
    my ($entries) = @_;
    return sort { $entries->{$b}->{create_ts} <=> $entries->{$a}->{create_ts} } keys %$entries;
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
    noindex         => \%noindex,
  );
  $gen->generate;

  # Hook: end
  $plugins->call_all('end');

  $self;
}

1;

__END__

=head1 NAME

Statik - top-level class of the Statik blogging engine

=head1 SYNOPSIS

  use Statik;

  # Constructor
  $statik = Statik->new(
    config      => $statik_configfile_path,
  );

  # Generate/refresh output pages
  $statik->generate;

=head1 DESCRIPTION

Statik is the top-level class of the Statik blogging engine.

=head1 SEE ALSO

L<statik>, L<Statik::Stash>, L<Statik::Generator>, L<Statik::Plugin>

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011-2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

