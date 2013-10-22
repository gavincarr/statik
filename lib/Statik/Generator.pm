package Statik::Generator;

use strict;
use Carp;
use File::Copy qw(move);
use File::stat;
use File::Basename;
use File::Path qw(make_path);
use Time::Piece;

use Statik::Stash;
use Statik::Util qw(clean_path);

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check required arguments
  for (qw(config options posts plugins entries_map entries_list generate_paths noindex)) {
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

# Generate pages for all page_paths
sub generate {
  my $self = shift;

  for my $path (sort keys %{ $self->{generate_paths} }) {
    if (-f File::Spec->catfile($self->{config}->{post_dir}, $path)) {
      $self->generate_post_pages(path_filename => $path);
    }
    elsif (my $posts = $self->{generate_paths}->{$path}) {
      $self->generate_index_pages(path => $path, posts => $posts);
    }
  }
}

# Generate single post pages (one per post_flavour) for the given path element
sub generate_post_pages {
  my ($self, %arg) = @_;

  # Check arguments
  my $path_filename = delete $arg{path_filename} 
    or die "Required argument 'path_filename' missing";

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

    print "+ Generating $flavour post page for '$path_filename'\n"
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

# Generate index (multi-post) pages (one per index_flavour) for $path
sub generate_index_pages {
  my ($self, %arg) = @_;

  # Check arguments
  my $path = delete $arg{path};
  die "Required argument 'path' missing" unless defined $path;
  my $posts = delete $arg{posts}
    or die "Required argument 'posts' missing";
  ref $posts and ref $posts eq 'ARRAY'
    or die "Invalid 'posts' argument '$posts' - not an arrayref";

  # If @$posts == 0, we should delete all existing index pages
  if (@$posts == 0) {
    $self->_remove_all_index_pages(path => $path);
    return;
  }

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
    my (@page_files, @page_sets);
    my $page_num = 1;
    my $output;
    my $index_mtime = 0;
    for my $post_fullpath (@$posts) {
      die "Missing post file '$post_fullpath'" unless -f $post_fullpath;
      push @page_files, $post_fullpath unless $self->{noindex}->{$post_fullpath};

      my $mtime = stat($post_fullpath)->mtime;
      $index_mtime = $mtime if $mtime > $index_mtime;

      if (@page_files == $posts_per_page) {
        push @page_sets, [ @page_files ];

        @page_files = ();
        $page_num++;
        last if $max_pages && $page_num > $max_pages;
      }
    }
    # Push any final partial page set
    push @page_sets, [ @page_files ] if @page_files;

    # Now generate pages for each of the page sets
    my $page_total = @page_sets;
    $page_num = 1;
    for my $page_files (@page_sets) {
      printf "+ Generating %s index page %d/%d for '%s' (entries = %d)\n",
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

      # Only ever generate a single atom page
      last if $flavour eq 'atom';
    }
  }
}

sub _remove_all_index_pages {
  my ($self, %arg) = @_;

  # Check arguments
  my $path = delete $arg{path} 
    or die "Required argument 'path' missing";

  # Remove all index pages in $path
  my $config = $self->{config};
  for my $flavour (@{$config->{index_flavours}}) {
    my $fconfig = $config->flavour($flavour);
    my $suffix = $fconfig->{suffix} || $flavour;
    for (glob "$config->{static_dir}/$path/index*.$suffix") {
      print "+ Removing obsolete $_\n" if $self->{options}->{verbose};
      unlink $_;
    }
  }

  # Remove directory if empty
  if (! glob "$config->{static_dir}/$path/*") {
    rmdir "$config->{static_dir}/$path";
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
  $stash->xml_escape_text;
  $output .= $interpolate_sub->( template => $head_tmpl, stash => $stash );

  # Process posts
  my $current_date = '';
  for (my $i = 0; $i <= $#$post_fullpaths; $i++) {
    my ($date_output, $post_output);
    ($date_output, $post_output, $current_date) = $self->_generate_post(
      post_fullpath => $post_fullpaths->[$i],
      flavour       => $flavour,
      theme         => $theme,
      stash         => $stash,
      current_date  => $current_date,
    );

    $output .= $date_output if defined $date_output;
    $output .= $post_output;
  }

  # Foot hook
  my $foot_tmpl = $template_sub->( chunk => 'foot', flavour => $flavour, theme => $theme );
  $self->{plugins}->call_all( 'foot', template => \$foot_tmpl, stash => $stash );
  $stash->xml_escape_text;
  $output .= $interpolate_sub->( template => $foot_tmpl, stash => $stash );

  return $output if $output;
}

# Generate/render the flavour/themed output for a post.
# Called once per post per theme/flavour.
# Returns a three-element list: ($date_output, $post_output, $current_date).
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
  my $current_date = delete $arg{current_date};
  die "Required argument 'current_date' missing" unless defined $current_date;
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my $template_sub = $self->{template_sub};

  # Fetch parsed post
  my $post = $self->{posts}->fetch(path => $post_fullpath);

  # Update stash with post data. There are also xml-escaped versions of these called X_esc.
  # post_fullpath is the absolute path to the text post file, including file_extension
  # post_path is the post_fullpath path relative to post_dir, and without the filename
  # post_filename is the post_fullpath basename without the file_extension
  # post_extension is the file extension
  my ($post_filename, $post_path) = fileparse($post_fullpath);
  die "Post file '$post_fullpath' has unexpected format - aborting" 
    unless $post_fullpath && $post_path;
  $post_path =~ s!^$self->{config}->{post_dir}/!!;
  $post_path = clean_path($post_path);
  my $post_extension;
  if ($post_filename =~ m/^(.*)\.([^.]+)$/) {
    $post_filename = $1;
    $post_extension = $2;
  }

  # Post path entries
  $stash->set(post_fullpath => $post_fullpath);
  $stash->set_as_path(post_path => $post_path);
  $stash->set(post_filename => $post_filename);
  $stash->set(post_extension => $post_extension);

  # Post date entries
  $stash->set_as_date(post_created  => $self->{entries_map}->{$post_fullpath}->{create_ts});
  $stash->set_as_date(post_updated  => $self->{entries_map}->{$post_fullpath}->{modify_ts});

  # post_headers are lowercased and mapped into header_xxx fields
  $stash->delete_all(qr/^header_/);
  $stash->set("header_\L$_" => $post->headers->{$_}) foreach keys %{$post->{headers}};
  $stash->set(body          => $post->body);

  # Date hook
  my $date_output;
  if ($stash->{post_created_date} ne $current_date) {
    my $date_tmpl = $template_sub->( chunk => 'date', flavour => $flavour, theme => $theme );
    $self->{plugins}->call_all( 'date', template => \$date_tmpl, stash => $stash );
    $stash->xml_escape_text;
    $date_output = $self->{interpolate_sub}->( template => $date_tmpl, stash => $stash );
    $stash->set(date_break => 1);
  }
  else {
    $stash->set(date_break => 0);
  }

  # Post hook
  my $post_tmpl = $template_sub->( chunk => 'post', flavour => $flavour, theme => $theme );
  $self->{plugins}->call_all( 'post', template => \$post_tmpl, stash => $stash );
  $stash->xml_escape_text;
  my $post_output = $self->{interpolate_sub}->( template => $post_tmpl, stash => $stash );

  return ($date_output, $post_output, $stash->{post_created_date});
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
    print "+ Creating output for $fullpath\n";
    return;
  }
  
  # Check required directories exist
  my $dir = dirname $fullpath;
  -d $dir or make_path($dir, { mode => 0755 });

  # Write tmp output file
  open my $fh, '>', "$fullpath.tmp"
    or die "Cannot open output file '$fullpath.tmp': $!";
  binmode $fh, ":encoding($self->{config}->{blog_encoding})";
  print $fh $output
    or die "Cannot write to '$fullpath': $!";
  close $fh
    or die "Close on '$fullpath' failed: $!";

  # Rename tmp output file to real one
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

