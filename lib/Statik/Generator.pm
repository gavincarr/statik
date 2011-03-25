package Statik::Generator;

use strict;
use Carp;
use Clone qw(clone);
use File::Copy qw(move);
use File::stat;
use File::Basename;
use Time::Piece;

use Statik::Parser;
use Statik::Stash;

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  for (qw(config options plugins files files_list)) {      # required
    $self->{$_} = delete $arg{$_} 
      or croak "Required argument '$_' missing";
  }
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  ($self->{template_sub}) = $self->{plugins}->call_first('template')
    or die "No template plugin found - aborting";
  $self->{interpolate_sub} = sub {
    my %arg = @_;
    my $template = delete $arg{template};
    my $stash = delete $arg{stash};

    # Interpolate simple $name or ${name} variables if found in stash
    $template =~ s/(?<!\\) \$ \{? (\w+) \}? \n?
                  /defined $stash->{$1} ? $stash->{$1} : ''/gex;

    return $template;
  };

  $self;
}

# Generate updated post and index pages for the given post files
sub generate_updates {
  my ($self, %arg) = @_;

  # Check arguments
  my $updates = delete $arg{updates} 
    or die "Required argument 'updates' missing";
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my @updates = sort keys %$updates or return;
  printf "+ Generating pages for %d updated posts\n", scalar @updates
    if $self->{options}->{verbose};

  $self->_generate_index_pages('');

  my %done = ( '' => 1 );
  for my $path (@updates) {
    my $current_path = '';
    my @path_elt = split m!/!, $path;
    while (my $path_elt = shift @path_elt) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
print "$current_path\n";
      if (@path_elt) {
        $self->_generate_index_pages($current_path);
      }
      else {
        $self->_generate_post_pages($current_path);
      }
    }
  }
}

# Generate single post pages (one per post_flavour) for the given path element
sub _generate_post_pages {
  my ($self, $path_filename) = @_;
  my $config = $self->{config};
  die "Path does not end in .$config->{file_extension}"
    unless $path_filename =~ m/\.$config->{file_extension}$/o;

  # Iterate over flavours
  for my $flavour (@{$config->{post_flavours}}) {
    my $fconfig = $config->flavour($flavour);
    my $suffix = $fconfig->{suffix} || $flavour;
    my $theme = $fconfig->{theme} || 'default';
    my $path = dirname $path_filename;
    my $post_fullpath = "$config->{post_dir}/$path_filename";
    my $output_fullpath = "$config->{static_dir}/$path_filename";
    $output_fullpath =~ s/\.$config->{file_extension}$/.$suffix/;

    print "+ generating $flavour post page for '$path_filename'\n"
      if $self->{options}->{verbose};
    my $output = $self->_generate_page(
      flavour => $flavour,
      suffix => $suffix,
      theme => $theme,
      path => $path,
      post_fullpaths => $post_fullpath,
    );

    $self->_output(output => $output, fullpath => $output_fullpath);
  }
}

# Generate index (multi-post) pages (one per index_flavour) for the given path element
sub _generate_index_pages {
  my ($self, $path) = @_;
  my $config = $self->{config};

  mkdir "$config->{static_dir}/$path", 0755
    unless -d "$config->{static_dir}/$path" || $self->{options}->{noop};
  for my $flavour (@{$config->{index_flavours}}) {
    # Get theme, posts_per_page and max_pages settings
    my $fconfig = $config->flavour($flavour);
    my $suffix = $fconfig->{suffix} || $flavour;
    my $theme = $fconfig->{theme} || 'default';
    my $posts_per_page = $fconfig->{posts_per_page};
    $posts_per_page = $config->{posts_per_page} 
      unless $posts_per_page;
    my $max_pages = $fconfig->{max_pages};
    $max_pages = $config->{max_pages} 
      unless defined $max_pages && $max_pages ne '';

    # Group post files into N sets of $posts_per_page posts
    # (we do this in two passes to calculate page_total before we render)
    my $files = clone $self->{files};
    my (@page_files, @page_sets);
    my $page_num = 1;
    my $output;
    my $index_mtime = 0;
    for my $post_fullpath (@{ $self->{files_list} }) {
      die "Missing post file '$post_fullpath'" unless -f $post_fullpath;
      (my $post_file = $post_fullpath) =~ s!^$self->{config}->{post_dir}/!!;

      # Only interested in posts within $path
      next if $path && $post_file !~ m/^$path\b/;
      push @page_files, $post_fullpath;

      my $mtime = stat($post_fullpath)->mtime;
      $index_mtime = $mtime if $mtime > $index_mtime;

      if (@page_files == $posts_per_page) {
        push @page_sets, [ @page_files ];

        @page_files = ();
        $page_num++;
        last if $page_num > $max_pages;
      }
    }
    # Push any final partial page set
    push @page_sets, [ @page_files ] if @page_files;

    # Now generate pages for each of the page sets
    my $page_total = @page_sets;
    $page_num = 1;
    for my $page_files (@page_sets) {
      printf "+ generating %s index page %d/%d for '%s' (entries = %d)\n",
        $flavour, $page_num, $page_total, $path || '/', scalar @$page_files
          if $self->{options}->{verbose};
      $output = $self->_generate_page(
        flavour         => $flavour,
        suffix          => $suffix,
        theme           => $theme,
        path            => $path,
        post_fullpaths  => $page_files,
        page_num        => $page_num,
        page_total      => $page_total,
        index_mtime     => $index_mtime,
        is_index        => 1,
      );

      $self->_output(output => $output, 
        path => $path, suffix => $suffix, page_num => $page_num);

      @page_files = ();
      $page_num++;
    }
  }
}

# Generate the output for a given page
sub _generate_page {
  my ($self, %arg) = @_;

  # Check arguments
  my $flavour = delete $arg{flavour} 
    or die "Required argument 'flavour' missing";
  my $theme = delete $arg{theme}
    or die "Required argument 'theme' missing";
  my $suffix = delete $arg{suffix} 
    or die "Required argument 'suffix' missing";
  my $post_fullpaths = delete $arg{post_fullpaths}
    or die "Required argument 'post_fullpaths' missing";
  my $page_num = delete $arg{page_num} || 1;
  my $page_total = delete $arg{page_total} || 1;
  my $is_index = delete $arg{is_index};
  my $index_mtime = delete $arg{index_mtime};
  my $path = delete $arg{path};
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;
  $post_fullpaths = [ $post_fullpaths ] unless ref $post_fullpaths;

  # Setup stash
  my $stash = Statik::Stash->new(config => $self->{config}, flavour => $flavour);
  $stash->set(page_num      => $page_num);
  $stash->set(page_total    => $page_total);
  $stash->set(is_index      => $is_index);
  $stash->set_as_path(path  => $path);
  $stash->set_as_date(index_updated => $index_mtime) if $index_mtime;

  my $template_sub = $self->{template_sub};
  my $interpolate_sub = $self->{interpolate_sub};
  my $output = '';

  # Head hook
  my $head_tmpl = $template_sub->( chunk => 'head', flavour => $flavour, theme => $theme );
  $self->{plugins}->call_all( 'head', template => \$head_tmpl, stash => $stash );
  $output .= $interpolate_sub->( template => $head_tmpl, stash => $stash );

  # Posts
  my $current_date = '';
  for (my $i = 0; $i <= $#$post_fullpaths; $i++) {
    my ($date_output, $post_output) = $self->_generate_post(
      post_fullpath => $post_fullpaths->[$i],
      flavour       => $flavour,
      theme         => $theme,
      stash         => $stash,
    );
    my $post_date = $stash->{post_created_date};
    $output .= $date_output if $post_date && $post_date ne $current_date;
    $output .= $post_output;
    $current_date = $post_date;
  }

  # Foot hook
  my $foot_tmpl = $template_sub->( chunk => 'foot', flavour => $flavour, theme => $theme );
  $self->{plugins}->call_all( 'foot', template => \$foot_tmpl, stash => $stash );
  $output .= $interpolate_sub->( template => $foot_tmpl, stash => $stash );

  return $output if $output;
}

# Generate/render the flavour/themed output for a post.
# Called once per post per theme/flavour.
# Returns a two-element list: ($date_output, $post_output).
sub _generate_post {
  my ($self, %arg) = @_;

  # Check arguments
  my $post_fullpath = delete $arg{post_fullpath}
    or die "Required argument 'post_fullpath' missing";
  my $flavour = delete $arg{flavour} 
    or die "Required argument 'flavour' missing";
  my $theme = delete $arg{theme} 
    or die "Required argument 'theme' missing";
  my $stash = delete $arg{stash}
    or die "Required argument 'stash' missing";
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my $template_sub = $self->{template_sub};

  # Parse post
  my $post = Statik::Parser->new(
    file => $post_fullpath,
    # TODO: maybe we should have a separate file_encoding setting?
    encoding => $self->{config}->{blog_encoding},
  );

  # Update stash with post data (note there are also X_unesc versions of
  # these if flavour.xml_escape is set - which is the default)
  # post_fullpath is the absolute path to the text post file, including file_extension
  # post_path is the post_fullpath path relative to post_dir, and without the filename
  # post_filename is the post_fullpath basename without the file_extension
  my ($post_filename, $post_path) = fileparse($post_fullpath, $self->{config}->{file_extension});
  die "Post file '$post_fullpath' has unexpected format - aborting" 
    unless $post_fullpath && $post_path;
  $post_path =~ s!^$self->{config}->{post_dir}/!!;
  $post_filename =~ s!\.$!!;

  # Post path entries
  $stash->set(post_fullpath => $post_fullpath);
  $stash->set_as_path(post_path => $post_path);
  $stash->set(post_filename => $post_filename);

  # Post date entries
  $stash->set_as_date(post_created  => $self->{files}->{$post_fullpath});
  $stash->set_as_date(post_updated  => stat($post_fullpath)->mtime);

  # post_headers are lowercased and mapped into header_xxx fields
  $stash->set("header_\L$_" => $post->headers->{$_}) foreach keys %{$post->{headers}};
  $stash->set(body          => $post->body);

  # Date hook
  my $date_tmpl = $template_sub->( chunk => 'date', flavour => $flavour, theme => $theme );
  $self->{plugins}->call_all( 'date', template => \$date_tmpl, stash => $stash );
  my $date_output = $self->{interpolate_sub}->( template => $date_tmpl, stash => $stash );

  # Post hook
  my $post_tmpl = $template_sub->( chunk => 'post', flavour => $flavour, theme => $theme );
  $self->{plugins}->call_all( 'post', template => \$post_tmpl, stash => $stash );
  my $post_output = $self->{interpolate_sub}->( template => $post_tmpl, stash => $stash );

  return ($date_output, $post_output);
}

sub _output {
  my ($self, %arg) = @_;

  my $output = delete $arg{output}
    or die "Required argument 'output' missing";
  my $fullpath = delete $arg{fullpath};
  my $path = delete $arg{path};

  $fullpath ||= File::Spec->catfile(
    $self->{config}->{static_dir},
    $path ? $path : (),
    $self->_generate_filename(%arg)
  );
  
  if ($self->{options}->{noop}) {
    print "+ outputting $fullpath\n";
    return;
  }

  open my $fh, '>', "$fullpath.tmp"
    or die "Cannot open output file '$fullpath.tmp': $!";
  binmode $fh, ":encoding($self->{config}->{blog_encoding})";
  print $fh $output
    or die "Cannot write to '$fullpath': $!";
  close $fh
    or die "Close on '$fullpath' failed: $!";

  move "$fullpath.tmp", $fullpath
    or die "Renaming $fullpath.tmp -> $fullpath failed: $!";
}

sub _generate_filename {
  my ($self, %arg) = @_;

  my $suffix = delete $arg{suffix}
    or die "Required argument 'suffix' missing";
  my $page_num = delete $arg{page_num} || 1;

  return sprintf 'index%s.%s', $page_num == 1 ? '' : $page_num, $suffix;
}

1;

=head1 NAME

Statik::Generator - class for generating actual statik output pages

=head1 SYNOPSIS

  use Statik::Generator;



=head1 DESCRIPTION

Statik::Generator is the statik class responsible for the actual generation
of statik output pages.

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

