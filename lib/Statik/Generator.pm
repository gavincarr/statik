
package Statik::Generator;

use strict;
use Carp;
use Clone qw(clone);
use File::Copy qw(move);
use File::stat;
use Time::Piece;

use Statik::Parser;
use Statik::Stash;

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
    or die "Required argument 'updates' missing";
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  my @updates = sort keys %$updates or return;
  printf "+ Generating pages for %d updated posts\n", scalar @updates
    if $self->{verbose};

  $self->_generate_index_pages('');

  my %done = ( '' => 1 );
  for my $path (@updates) {
    my $current_path = '';
    my @path_elt = split m!/!, $path;
    while (my $path_elt = shift @path_elt) {
      $current_path .= '/' if $current_path;
      $current_path .= $path_elt;
      next if $done{$current_path}++;
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
  my ($self, $path) = @_;
  my $config = $self->{config};
  die "Path does not end in .$config->{file_extension}"
    unless $path =~ m/\.$config->{file_extension}$/o;

  # Iterate over flavourrs
  for my $flavour (@{$config->{post_flavours}}) {
    my $fconfig = $config->flavour($flavour);
    my $suffix = $fconfig->{suffix} || $flavour;
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
    (my $output_file = $path) =~ s/\.$config->{file_extension}$/.$suffix/;

    print "+ generating $flavour post page for '$path'\n" if $self->{verbose};
    my $output = $self->_generate_page(
      flavour => $flavour,
      suffix => $suffix,
      theme => $theme,
      post_files => $path,
      post_template => $post_tmpl,
    );

    $self->_output(output => $output, filename => $output_file);
  }
}

# Generate index (multi-post) pages (one per index_flavour) for the given path element
sub _generate_index_pages {
  my ($self, $path) = @_;
  my $config = $self->{config};

  mkdir "$config->{static_dir}/$path", 0755
    unless -d "$config->{static_dir}/$path" || $self->{noop};
  for my $flavour (@{$config->{index_flavours}}) {
    # Get theme, posts_per_page and max_pages settings
    my $fconfig = $config->flavour($flavour);
    my $suffix = $fconfig->{suffix} || $flavour;
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

    # Group post files into N sets of $posts_per_page posts
    # (we do this in two passes to calculate page_total before we render)
    my $files = clone $self->{files};
    my (@page_files, @page_sets);
    my $page_num = 1;
    my $output;
    my $index_mtime = 0;
    for my $post_file ( $self->{sort_sub}->($files) ) {
      $post_file =~ s!$self->{config}->{post_dir}/!!;

      # Only interested in posts within $path
      next if $path && $post_file !~ m/^$path\b/;

      push @page_files, $post_file;
      my $post_fullpath = "$self->{config}->{post_dir}/$post_file";
      my $mtime = stat($post_fullpath)->mtime;
      $index_mtime = $mtime if $mtime > $index_mtime;

      if (@page_files == $posts_per_page) {
        push @page_sets, [ @page_files ];

        @page_files = ();
        $page_num++;
        last if $page_num > $max_pages;
      }
    }

    # Now generate pages for each of the page sets
    my $page_total = @page_sets;
    $page_num = 1;
    for my $page_files (@page_sets) {
      printf "+ generating %s index page %d/%d for '%s' (entries = %d)\n",
        $flavour, $page_num, $page_total, $path || '/', scalar @$page_files
          if $self->{verbose};
      $output = $self->_generate_page(
        flavour         => $flavour,
        suffix          => $suffix,
        theme           => $theme,
        path            => $path,
        post_files      => $page_files,
        post_template   => $post_tmpl,
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
  my $suffix = delete $arg{suffix} 
    or die "Required argument 'suffix' missing";
  my $post_files = delete $arg{post_files}
    or die "Required argument 'post_files' missing";
  my $post_tmpl = delete $arg{post_template}
    or die "Required argument 'post_template' missing";
  my $page_num = delete $arg{page_num} || 1;
  my $page_total = delete $arg{page_total} || 1;
  my $theme = delete $arg{theme};
  my $is_index = delete $arg{is_index};
  my $index_mtime = delete $arg{index_mtime};
  my $path = delete $arg{path};
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;
  $path = $post_files unless defined $path || ref $post_files;

  $post_files = [ $post_files ] unless ref $post_files;
  my $output = '';
  my $template_sub = $self->{template_sub};
  my $interpolate_sub = $self->{interpolate_sub};

  # Setup stash
  my $stash = Statik::Stash->new(config => $self->{config}, flavour => $flavour);
  $stash->set(page_num      => $page_num);
  $stash->set(page_total    => $page_total);
  $stash->set(is_index      => $is_index);
  $stash->set(path          => $path);
  $stash->set(path_abs      => "/$path");
  $self->_set_stash_dates($stash, 'index_updated', $index_mtime) if $index_mtime;

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

  return $output if $output;
}

sub _generate_post {
  my ($self, %arg) = @_;

  # Check arguments
  my $post_file = delete $arg{post_file}
    or die "Required argument 'post_file' missing";
  my $post_tmpl = delete $arg{post_template}
    or die "Required argument 'post_template' missing";
  my $stash = delete $arg{stash}
    or die "Required argument 'stash' missing";
  die "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  # Parse post
  my $post = Statik::Parser->new(
    file => "$self->{config}->{post_dir}/$post_file",
    # TODO: maybe we should have a separate file_encoding setting?
    encoding => $self->{config}->{blog_encoding},
  );

  # Update stash with post data (and there are X_unesc versions of these as well
  # if flavour is set to xml_escape = yes (which is the default)
  # post_path is set to the post_file (relative) path without the final suffix
  (my $post_path = $post_file) =~ s/\.$self->{config}->{file_extension}$//o;
  $stash->set(post_path     => $post_path);
  $stash->set(post_path_abs => "/$post_path");
  # post_headers are lowercased and mapped into header_xxx fields
  $stash->set("header_\L$_" => $post->headers->{$_}) foreach keys %{$post->{headers}};
  # post body is able in the 'body' field
  $stash->set(body          => $post->body);
  # Post date entries
  my $post_fullpath = "$self->{config}->{post_dir}/$post_file";
  $self->_set_stash_dates($stash, 'post_created', $self->{files}->{$post_fullpath});
  $self->_set_stash_dates($stash, 'post_updated', stat($post_fullpath)->mtime);

  # Post hook
  $self->{plugins}->call_all('post',
    path          => $post_path,
    template      => \$post_tmpl,
    post          => $post,
    stash         => $stash,
  );

  return $self->{interpolate_sub}->( template => $post_tmpl, stash => $stash );
}

sub _output {
  my ($self, %arg) = @_;

  my $output = delete $arg{output}
    or die "Required argument 'output' missing";
  my $path_filename = delete $arg{filename};

  $path_filename ||= $self->_generate_filename(%arg);
  my $static_path_filename = "$self->{config}->{static_dir}/$path_filename";
  
  if ($self->{noop}) {
    print "+ outputting $path_filename\n";
    return;
  }

  open my $fh, '>', "$static_path_filename.tmp"
    or die "Cannot open output file '$static_path_filename.tmp': $!";
  binmode $fh, ":encoding($self->{config}->{blog_encoding})";
  print $fh $output
    or die "Cannot write to '$static_path_filename': $!";
  close $fh
    or die "Close on '$static_path_filename' failed: $!";

  move "$static_path_filename.tmp", $static_path_filename
    or die "Renaming $static_path_filename.tmp to non-tmp version failed: $!";
}

sub _generate_filename {
  my ($self, %arg) = @_;

  my $path = delete $arg{path};
  die "Required argument 'path' missing" unless defined $path;
  my $suffix = delete $arg{suffix}
    or die "Required argument 'suffix' missing";
  my $page_num = delete $arg{page_num} || 1;

  $path .= '/' unless substr($path,-1) eq '/';
  return sprintf "%sindex%s.%s", $path, $page_num == 1 ? '' : $page_num, $suffix;
}

sub _set_stash_dates {
  my ($self, $stash, $label, $epoch) = @_;
  die "epoch unset for $stash->{post_path} / $label" if ! defined $epoch;

  my $t = ref $epoch ? $epoch : Time::Piece->strptime($epoch, '%s');

  $stash->set("${label}_epoch"      => $t->epoch);
  $stash->set("${label}_date"       => $t->strftime('%Y-%m-%d'));
  $stash->set("${label}_iso8601"    => $t->strftime('%Y-%m-%dT%T%z'));
}

1;
