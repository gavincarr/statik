# Name: Statik::Plugin::SHJS
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::SHJS'

package Statik::Plugin::SHJS;

use strict;
use parent qw(Statik::Plugin);
use File::Basename;

# Uncomment next line to enable ### line debug output
#use Smart::Comments

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::SHJS] section to
# your statik.conf config, and update as key = value entries.

sub defaults {
  return {};
}

# -------------------------------------------------------------------------
# Hooks

sub post {
  my ($self, %arg) = @_;
  my $stash = $arg{stash};
  my $body = $self->_munge_body($stash->{body});
  $stash->{body} = $body if $body ne $stash->{body};
}

sub _munge_body {
  my ($self, $body) = @_;

  my @code = ($body =~ m{<pre><code>(.*?)</code></pre>}sg);

  my $count = 1;
  for my $code (@code) {
    if ($code =~ m{^\s*((?:#!|```)([\w/]+)\r?\n?)}) {
      my $code_initial = $code;
      my $snippet = $1;
      my $shebang = $2;
      my $filetype = basename $2;
      $filetype = 'sh' if $filetype eq 'bash';
      # Remove filetype indicator if a simplified shebang
      $code =~ s/$snippet// if $shebang !~ m{/};

      # debug(1, "found code block $count, filetype '$filetype'"); $count++;

      # Update $body, modifying pre class
      $body =~ s{<pre><code>\Q$code_initial\E</code></pre>}
                {<pre class="sh_$filetype">\n$code</pre>};
    }
  }

  return $body;
}

1;

=head1 NAME

Statik::Plugin::SHJS - Statik plugin that converts code block shebangs
for the SHJS syntax highlighter

=head1 SYNOPSIS

No configuration options.

=head1 DESCRIPTION

Statik::Plugin::SHJS is a Statik plugin that converts code block shebangs
for the SHJS syntax highlighter.

The plugin looks for  <pre><code>...</code></pre> blocks (which is what
Markdown produces), where the first line in the block is a simplified
shebang, of the form:

    #!perl

If it finds such a block, it removes the shebang line and modifies the
<pre> to the form that shjs expects i.e.

    <pre class="sh_perl">

in this case.

=head1 USAGE

Should be placed after any plugins that create code blocks for you
e.g. Markdown.

Requires the SHJS javascript and css files to be available
in the locations defined by the $config{javascript_path} and
$config{css_path} variables, and the appropriate script and css
inclusions to be in the theme files you're using.

See L<http://shjs.sourceforge.net/doc/documentation.html> for SHJS
installation documentation.

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>

=head1 COPYRIGHT AND LICENCE

Copyright (C) Gavin Carr 2011-2013.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.0 or, at
your option, any later version of Perl 5.

=cut

