# Name: Statik::Plugin::Theme
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Theme'

package Statik::Plugin::Theme;

use strict;
use parent qw(Statik::Plugin);

# Uncomment next line to enable debug output (don't uncomment debug() lines)
#use Blosxom::Debug debug_level => 1;

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::Theme] section to 
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # In what directory are your themes? (if relative, 'base_dir' is prefixed)
    theme_dir               => 'themes',
    # In what directory are your public resources (css, js, images, etc.)
    # (if relative, 'base_dir' is prefixed)
    public_dir              => 'public',
    # What's the URL of your public directory (if relative, 'url' is prefixed)
    public_url              => 'public',
  };
}

# -------------------------------------------------------------------------

sub start {
  my $self = shift;
  $self->{cache} = {};
  my $config = $self->config;

  # Qualify config items if required
  $self->{theme_dir} = "$config->{base_dir}/$self->{theme_dir}"
    if substr($self->{theme_dir},0,1) ne '/';
  $self->{public_dir} = "$config->{base_dir}/$self->{public_dir}"
    if substr($self->{public_dir},0,1) ne '/';
  $self->{public_url} = "$config->{url}$self->{public_url}"
    if substr($self->{public_url},0,1) ne '/';
}

# Template hook - return a subroutine that takes named 'flavour', 'theme' and 
# 'chunk' parameters and returns the appropriate template chunk (uninterpolated)
sub template {
  my $self = shift;

  return sub {
    my %args = @_;

    my $chunk = $args{chunk} ||
      die "[Plugin::Theme] missing 'chunk' argument to template()";
    my $flavour = $args{flavour} || 
      die "[Plugin::Theme] missing 'flavour' argument to template()";
    my $theme = $args{theme} || 'default';
    $theme = 'default' unless -d "$self->{theme_dir}/$theme";

    # Return cached chunk if available
    return $self->{cache}->{$flavour}->{$chunk} || ''
      if $self->{cache}->{$flavour};

    # Parse all chunks from theme flavour page
#   my $page = "$self->{theme_dir}/$theme/page.$flavour";
    my $page = "$self->{theme_dir}/$theme.$flavour";
    die "[Plugin::Theme] cannot find '$flavour' template for '$theme' theme in $self->{theme_dir}\n"
      unless -r $page;
#   return '' unless -r $page;
    if (open my $fh, '<', $page) {
      my $current_chunk = '';
      while (my $line = <$fh>) {
        if ($line =~ m/<!-- \s* statik \s+ (\w+) (?:\s+(.*)\b)? \s* -->/x) {
          if ($1 && $2) {
            $self->{cache}->{$flavour}->{$1} = $2;
            $current_chunk = '';
          }
          else {
            my $next_chunk = $1;
            # Trim current_chunk trailing whitespace before updating to next
            $self->{cache}->{$flavour}->{$current_chunk} =~ s/\s+\z/\n/s
              if $current_chunk;
            $current_chunk = $next_chunk;
          }
        }
        elsif ($current_chunk) {
          $self->{cache}->{$flavour}->{$current_chunk} .= $line;
        }
      }
      # Trim current_chunk trailing whitespace
      $self->{cache}->{$flavour}->{$current_chunk} =~ s/\s+\z/\n/s
        if $current_chunk;

      # Return newly-cached $chunk if we found one
      return $self->{cache}->{$flavour}->{$chunk} || '';
    }
  };
}

# Add config paths to stash
sub head {
  my ($self, %arg) = @_;
  $arg{stash}->set_as_path(theme_dir    => $self->{theme_dir});
  $arg{stash}->set_as_path(public_dir   => $self->{public_dir});
  $arg{stash}->set_as_path(public_url   => $self->{public_url});
}

1;

__END__

=head1 NAME

Statik::Plugin::Theme - default statik template plugin, returning template
chunks from named theme files

=head1 SYNOPSIS

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::Theme]
    # In what directory are your themes? (if relative, 'base_dir' is prefixed)
    theme_dir = themes
    # In what directory are your public resources (css, js, images, etc.)
    # (if relative, 'base_dir' is prefixed)
    public_dir = public
    # What's the URL of your public directory (if relative, 'url' is prefixed)
    public_url = public


=head1 DESCRIPTION

Statik::Plugin::Theme is the default statik template plugin, returning
template chunks from theme flavour pages.

Flavour pages are files that exist in your theme directory (theme_dir,
default 'themes'), with names of the form $theme.$flavour (e.g. 'default.html',
'default.atom'). Flavours are specified in the 'index_flavours' and
'post_flavours' entries in 'statik.conf'. The default values are:

=over 4

=item index_flavours = default.html,default.atom

=item post_flavours = default.html

=back

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011-2013, Gavin Carr.

This plugin is licensed under the terms of the GNU General Public Licence,
v3, or at your option, any later version.

=cut

# vim:ft=perl

