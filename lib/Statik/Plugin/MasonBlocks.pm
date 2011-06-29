# Name: Statik::Plugin::MasonBlocks
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::MasonBlocks'

package Statik::Plugin::MasonBlocks;

use strict;
use parent qw(Statik::Plugin);
use Text::MicroMason;

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::MasonBlocks]
# section to your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # Whether we munge post bodies as well as templates (default: no)
    munge_post_bodies => 0,
    # Comma-separated list of variables to default to '' in templates
    define_variables => '',
  };
}

# -------------------------------------------------------------------------

sub start {
  my $self = shift;
  $self->{mason} = Text::MicroMason->new
    or die "Mason instantiation failed: $!";
}

sub head {
  my $self = shift;
  $self->_munge_template(hook => 'head', @_);
}

sub date {
  my $self = shift;
  $self->_munge_template(hook => 'date', @_);
}

sub foot {
  my $self = shift;
  $self->_munge_template(hook => 'foot', @_);
}

sub post {
  my $self = shift;
  my %arg = @_;
  my $stash = $arg{stash};
  if ($self->{munge_post_bodies}) {
    $self->_munge_template(template => \$stash->{body}, stash => $stash);
    $self->_munge_template(template => \$stash->{body_unesc}, stash => $stash);
  }
  $self->_munge_template(hook => 'post', @_);
}

sub _munge_template {
  my ($self, %arg) = @_;
  my $template_ref = $arg{template};
  my $hook = $arg{hook} || '[unknown]';
  # TODO: should we clone this here, to avoid pollution, or do we want the continuity?
  my $stash = $arg{stash};

  # Add our define_variables list to stash
  for my $var (split /\s*,\s*/, $self->{define_variables}) {
    $stash->{$var} = '' if not defined $stash->{$var};
  }

  # Compile an arg list for Text::MicroMason. We could use -PassVariables
  # instead, but that only passes scalars, not e.g. $stash as a hashref
  my $args_section = "<%args>\n";
  $args_section .= "\$$_\n" foreach sort keys %$stash;
  $args_section .= "\$stash\n";
  $args_section .= "</%args>\n";

  # Execute the template
  my $munged = eval { 
    $self->{mason}->execute(
      text => "$args_section$$template_ref",
      {},
      %$stash,
      stash => $stash,
    ); 
  };
  if ($@) {
    # Text::MicroMason's errors are awful - truncate to the first line
    my @lines = split /\n/, $@;
    die "$hook template error: $lines[0]\n";
  }
  else {
    # Trim trailing whitespace
    $munged =~ s/\s+\z/\n/s;

    $$template_ref = $munged;
  }
}

1;

__END__

=head1 NAME

Statik::Plugin::MasonBlocks - adds support for mason-style conditionals and
comments to statik templates

=head1 SYNOPSIS

    # Allows the use of mason-style conditionals in your head/date/post/foot
    # templates. Any line beginning with a % is considered a directive.

    # Variables reference statik stash entries, so $post_author is a shortcut
    # for $stash->{post_author}.

    # Perl if, elsif, and else are fully supported, including nesting:
    % if ($post_author) {
    <author>
    %   if ($post_author_name) {
    <name>$post_author_name</name>
    %   } else {
    <name>$post_author</name>
    %   }
    </author>
    % }

    # Comments are any line beginning with %#
    %# This is a template comment

    # Longer comments can also be included inside <%doc>...</%doc> sections
    <%doc>
    This is a long
    important
    multi-line comment.
    </%doc>


=head1 DESCRIPTION

Statik::Plugin::MasonBlocks - adds support for mason-style conditionals and
comments to statik templates, using the Text::MicroMason perl module.

=head1 CONFIGURATION

To configure, add a section like the following to your statik.conf file
(defaults shown):

    [Statik::Plugin::MasonBlocks]
    munge_post_bodies = 0


=head1 SEE ALSO

L<Text:::MicroMason>

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011, Gavin Carr.

This software is free software, licensed under the same terms as perl itself.

=cut

# vim:ft=perl

