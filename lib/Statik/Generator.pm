
package Statik::Generator;

use strict;
use Carp;
use Clone qw(clone);
use Statik::Parser;

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, ref $class || $class;

  # Check arguments
  for (qw(config plugins files)) {      # required
    $self->{$_} = delete $arg{$_} 
      or croak "Required argument '$_' missing";
  }
  for (qw(verbose noop)) {              # optional
    $self->{$_} = delete $arg{$_};
  }
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  ($self->{template_sub}) = $self->{plugins}->call_first('template')
    or die "No template plugin found - aborting";
  $self->{interpolate_sub} = sub {
    my %arg = @_;
    my $template = delete $arg{template};
    my $stash = delete $arg{stash};

    # Interpolate simple $name variables if found in stash
    $template =~ s/\$(\w+)/defined $stash->{$1} ? $stash->{$1} : ''/ge;

    return $template;
  };
  $self->{sort_sub} = sub {
    my ($files) = @_;
    return sort { $files->{$b} <=> $files->{$a} } keys %$files;
  };

  $self;
}

# Generate updated post and index pages for the given post files
sub generate_updates {
  my ($self, %arg) = @_;

  # Check arguments
  my $updates = delete $arg{updates} 
    or croak "Required argument 'updates' missing";
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my @updates = sort keys %$updates or return;
  printf "+ Generating pages for %d updated posts\n", scalar @updates
    if $self->{verbose};

  $self->_generate_path_pages('');

  my %done = ( '' => 1 );
  for my $path (@updates) {
    my $current_path = '';
    for my $path_elt (split m!/!, $path) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
      $self->_generate_path_pages($current_path);
    }
  }
}

# Generate pages for the given path element (either a post or a directory)
sub _generate_path_pages {
  my ($self, $path) = @_;
# print "+ generate_path_pages: $path\n" if $self->{verbose};

  my $config = $self->{config};
  mkdir "$config->{static_dir}/$path", 0755
    unless -d "$config->{static_dir}/$path" || $self->{noop};

  # Single post page
  if ($path =~ m/\.$config->{file_extension}$/o) {
    for my $flavour (@{$config->{post_flavours}}) {
      my $fconfig = $config->flavour($flavour);
      my $theme = $fconfig->{theme} || 'default';
      my $post_tmpl = $self->{template_sub}->(
        chunk => 'post',
        flavour => $flavour,
        theme => $theme,
      );
      if (! $post_tmpl) {
        warn "WARNING: no post template found for '$flavour' flavour - skipping\n";
        return;
      }

      print "+ generating $flavour post page for '$path'\n" if $self->{verbose};
      my $output = $self->_generate_page(
        flavour => $flavour,
        theme => $theme,
        post_files => [ $path ],
        post_template => $post_tmpl,
      );

      # TODO: do stuff with $output
    }
  }

  # Index (multiple posts per page)
  else {
    for my $flavour (@{$config->{index_flavours}}) {
      # Get theme, posts_per_page  and max_pages settings
      my $fconfig = $config->flavour($flavour);
      my $theme = $fconfig->{theme} || 'default';
      my $posts_per_page = $fconfig->{posts_per_page};
      $posts_per_page = $config->{posts_per_page} 
        unless defined $posts_per_page;
      my $max_pages = $fconfig->{max_pages};
      $max_pages = $config->{max_pages} 
        unless defined $max_pages;

      my $post_tmpl = $self->{template_sub}->(
        chunk => 'post',
        flavour => $flavour,
        theme => $theme,
      );
      if (! $post_tmpl) {
        warn "WARNING: no post template found for '$flavour' flavour - skipping\n";
        return;
      }

      my $files = clone $self->{files};
      my $page_num = 1;
      my @page_files;
      my $output;
      for my $post_file ( $self->{sort_sub}->($files) ) {
        $post_file =~ s!$self->{config}->{post_dir}/!!;

        # Only interested in posts within $path
        next if $path && $post_file !~ m/^$path\b/;

        push @page_files, $post_file;
        if (@page_files == $posts_per_page) {
          printf "+ generating %s index page %d for '%s' (entries = %d)\n",
            $flavour, $page_num, $path || '/', scalar @page_files
              if $self->{verbose};
          $output = $self->_generate_page(
            flavour => $flavour,
            theme => $theme,
            post_files => \@page_files,
            post_template => $post_tmpl,
            page_num => $page_num,
            index => 1,
          );

          # TODO: do stuff with $output
#         my $filename = $path ? "$path/index.$flavour" : "index.$flavour";
#         print "+ generating index output $filename\n" if $self->{verbose};

          @page_files = ();
          $page_num++;
        }
      }

      # Output final partial page, if any
      if (@page_files) {
        printf "+ generating %s index page %d for '%s' (entries = %d)\n",
          $flavour, $page_num, $path || '/', scalar @page_files
              if $self->{verbose};
        $output = $self->_generate_page(
          flavour => $flavour,
          theme => $theme,
          post_files => \@page_files,
          post_template => $post_tmpl,
          page_num => $page_num,
          index => 1,
        );

        # TODO: do stuff with $output
      }
    }
  }
}

# Generate the output for a given page
sub _generate_page {
  my ($self, %arg) = @_;

  # Check arguments
  my $flavour = delete $arg{flavour} 
    or croak "Required argument 'flavour' missing";
  my $post_files = delete $arg{post_files}
    or croak "Required argument 'post_files' missing";
  my $post_tmpl = delete $arg{post_template}
    or croak "Required argument 'post_template' missing";
  my $page_num = delete $arg{page_num} || 1;
  my $theme = delete $arg{theme};
  my $index = delete $arg{index};
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my $output = '';
  my $template_sub = $self->{template_sub};
  my $interpolate_sub = $self->{interpolate_sub};
  my $stash = $self->{config}->to_stash;

  # Head
  my $head_tmpl = $template_sub->( chunk => 'head', flavour => $flavour, theme => $theme );
  $output .= $interpolate_sub->( template => $head_tmpl, stash => $stash );

  # Posts
  for (my $i = 0; $i <= $#$post_files; $i++) {
    $output .= $self->_generate_post(
      post_file => $post_files->[$i],
      post_template => $post_tmpl, 
      stash => $stash,
    );
  }

  # Foot
  my $foot_tmpl = $template_sub->( chunk => 'foot', flavour => $flavour, theme => $theme );
  $output .= $interpolate_sub->( template => $foot_tmpl, stash => $stash );

  print "\n$output\n" if $index;
  return $output if $output;
}

sub _generate_post {
  my ($self, %arg) = @_;

  # Check arguments
  my $post_file = delete $arg{post_file}
    or croak "Required argument 'post_file' missing";
  my $post_tmpl = delete $arg{post_template}
    or croak "Required argument 'post_template' missing";
  my $stash = delete $arg{stash}
    or croak "Required argument 'stash' missing";
# $stash = $self->{config}->to_stash;

  # Parse post
  my $post = Statik::Parser->new( file => "$self->{config}->{post_dir}/$post_file" );

  # Post hook
  $self->{plugins}->call_all('post',
    path          => $post,
    template      => \$post_tmpl,
    headers       => \{$post->headers},
    body          => \{$post->body},
  );

  # Update stash with post data
  $stash->{"header_\L$_"} = $post->headers->{$_} foreach keys %{$post->{headers}};
  $stash->{body} = $post->body;

  return $self->{interpolate_sub}->( template => $post_tmpl, stash => $stash );
}

1;
