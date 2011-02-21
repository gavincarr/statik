
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

  # Post file
  if ($path =~ m/\.$config->{file_extension}$/o) {
    for my $flavour (@{$config->{post_flavours}}) {
      my $theme;
      ($flavour, $theme) = split /:/, $flavour, 2 if $flavour =~ m/:/;
      (my $filename = $path) =~ s/\.$config->{file_extension}$/.$flavour/o;

      print "+ generating post output $filename\n" if $self->{verbose};
      my $output = $self->_generate_page(
        post => $path,
        flavour => $flavour,
        theme => $theme,
      );
    }
  }

  # Index
  else {
    mkdir "$config->{static_dir}/$path", 0755
      unless -d "$config->{static_dir}/$path" || $self->{noop};
    for my $flavour (@{$config->{index_flavours}}) {
      my $theme;
      ($flavour, $theme) = split /:/, $flavour, 2 if $flavour =~ m/:/;
      my $filename = $path ? "$path/index.$flavour" : "index.$flavour";

      print "+ generating index output $filename\n" if $self->{verbose};
      my $output = $self->_generate_page(
        path => $path,
        flavour => $flavour,
        theme => $theme,
      );
    }
  }
}

# Generate the output for a given page
sub _generate_page {
  my ($self, %arg) = @_;

  # Check arguments
  my $flavour = delete $arg{flavour} 
    or croak "Required argument 'flavour' missing";
  my $theme = delete $arg{theme};
  my $post_file = delete $arg{post};
  my $path = delete $arg{path}; 
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my $output = '';
  my $template_sub = $self->{template_sub};
  my $interpolate_sub = $self->{interpolate_sub};
  my $stash = $self->{config}->to_stash;

  # Head
  my $head_tmpl = $template_sub->( chunk => 'head', flavour => $flavour, theme => $theme );
  $output .= $interpolate_sub->( template => $head_tmpl, stash => $stash );

  # Posts
  my $post_tmpl = $template_sub->( chunk => 'post', flavour => $flavour, theme => $theme );
  if (! $post_tmpl) {
    warn "WARNING: no post template found for '$flavour' flavour - skipping\n";
    return;
  }

  # Single post
  if ($post_file) {
    $output .= $self->_generate_post(post_file => $post_file, post_template => $post_tmpl, stash => $stash);
  }

  # Index pages (multi-post)
  else {
    my $files = clone $self->{files};
    for $post_file ( $self->{sort_sub}->( $files ) ) {
      $post_file =~ s!$self->{config}->{post_dir}/!!;

      # Only interested in posts within $path
      next if $path && $post_file !~ m/^$path\b/;

      $output .= $self->_generate_post(post_file => $post_file, post_template => $post_tmpl, stash => $stash);
    }
  }

  # Foot
  my $foot_tmpl = $template_sub->( chunk => 'foot', flavour => $flavour, theme => $theme );
  $output .= $interpolate_sub->( template => $foot_tmpl, stash => $stash );

  print "\n$output\n" if ! $post_file;
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