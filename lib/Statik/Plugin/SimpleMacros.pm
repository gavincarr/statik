# Name: Statik::Plugin::SimpleMacros
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::SimpleMacros'

package Statik::Plugin::SimpleMacros;

use strict;
use parent qw(Statik::Plugin);
use File::Spec;
use YAML qw(LoadFile);
use Data::Dump qw(dd pp dump);

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::SimpleMacros]
# section to your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # Directory in which your macro definitions are located
    macro_directory => 'config/macros.d',
  };
}

# -------------------------------------------------------------------------

# Load macro files on startup
sub start {
  my $self = shift;
  $self->{macros} = [];
  if (my $dir = $self->{macro_directory}) {
    $dir = File::Spec->rel2abs($dir, $self->config->{base_dir});
    print "++ SimpleMacros dir: $dir\n"
      if $self->options->{verbose} >= 2;
    if (-d $dir) {
      for my $file (sort glob "$dir/*.yml") {
        my $macros = LoadFile($file);
        push @{ $self->{macros} }, @$macros;
      }
    }
  }
  print "++ SimpleMacros: " . dump($self->{macros}) . "\n"
    if $self->options->{verbose} >= 2;
}

# Munge posts
sub post {
  my ($self, %arg) = @_;
  my $stash = $arg{stash};
  for my $macro (@{ $self->{macros} }) {
    my $replace = 'qq{' . $macro->{replace} . '}';
    $stash->{body} =~ s/$macro->{pattern}/$replace/gee;
  }
}

1;

__END__

=head1 NAME

Statik::Plugin::SimpleMacros - adds support for simple macros for post bodies

=head1 DESCRIPTION

Statik::Plugin::SimpleMacros - adds support for simple macros that are applied
to post bodies. A macro is a just a mapping between a regex and a replacement
string - it's conceptually just doing a perl substitution on your post body:
s/$regex/$string/g.

=head1 CONFIGURATION

To configure, add a section like the following to your statik.conf file
(defaults shown, all settings are optional):

    [Statik::Plugin::SimpleMacros]
    macro_directory: config/macros.d

Macro files are YAML files (*.yml) stored in the macros directory (loaded in
string sorted order). Macro files should contain a list of hashes defining
individual macros. Each macro should be a hash containing two elements: a
'pattern', defining the regex string to match, and 'replace', defining the
replacement string to substitute.

Example macro file:

    ---
    -
      pattern: '"([^"]+)":((https?:/)?/[.\w#%/&;=~:?\@+-]+[\w#%/&=~:?\@+-])'
      replace: '<a href="${2}">${1}</a>'
    -
      pattern: '!\[(Yes)\]'
      replace: '<img src="/images/tick.png" alt="tick">'


=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011-2013, Gavin Carr.

This software is free software, licensed under the same terms as perl itself.

=cut

# vim:ft=perl

