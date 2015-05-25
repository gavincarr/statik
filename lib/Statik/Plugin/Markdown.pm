# Name: Statik::Plugin::Markdown
# Author(s): Gavin Carr <gavin@openfusion.com.au>
# Version: 0.001
# Documentation: see bottom of file or type 'perldoc Statik::Plugin::Markdown'

package Statik::Plugin::Markdown;

use strict;
use parent qw(Statik::Plugin);
use Text::MultiMarkdown qw(markdown);

# -------------------------------------------------------------------------
# Configuration defaults. To change, add a [Statik::Plugin::Markdown]
# section to your statik.conf config, and update as key = value entries.

sub defaults {
  return {
    # Flag indicating whether all posts will be in markdown format
    all_posts_are_markdown => 0,
    # Regex string of file extensions indicating posts in markdown format
    markdown_posts_extension_regex => '(md|mkd)',
  };
}

# -------------------------------------------------------------------------

sub start {
  my $self = shift;
}

sub post {
  my ($self, %arg) = @_;
  my $stash = $arg{stash};
  if ($self->{all_posts_are_markdown} ||
     ($self->{markdown_posts_extension_regex} &&
        $stash->{post_extension} =~ /$self->{markdown_posts_extension_regex}/)) {
    $self->_munge_template(template => \$stash->{body}, stash => $stash);
  }
}

sub _munge_template {
  my ($self, %arg) = @_;
  my $template_ref = $arg{template};
  $$template_ref = markdown($$template_ref, { empty_element_suffix => '>' });
}

1;

__END__

=head1 NAME

Statik::Plugin::Markdown - adds support for posts written in markdown

=head1 DESCRIPTION

Statik::Plugin::Markdown - adds support for posts formatted in markdown,
using the Text::MultiMarkdown perl module.

=head1 CONFIGURATION

To configure, add a section like the following to your statik.conf file
(defaults shown, all settings are optional):

    [Statik::Plugin::Markdown]
    all_posts_are_markdown = 0
    markdown_posts_extension_regex = (md|mkd)


=head1 SEE ALSO

L<Text:::MultiMarkdown>

=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>, http://www.openfusion.net/

=head1 LICENCE

Copyright 2011-2014, Gavin Carr.

This software is free software, licensed under the same terms as perl itself.

=cut

# vim:ft=perl

