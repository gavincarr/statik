package Statik::Config;

use strict;
use FindBin qw($Bin);
use Cwd qw(realpath);
use File::Spec;
use File::Basename;
use Config::Tiny;
use Encode qw(decode);
use Hash::Merge qw(merge);
use URI;

use Statik::Util qw(clean_path);

my @main_required    = qw(url author_name blog_id_year);
my %main_booleans    = map { $_ => 1 } qw(show_future_entries);
my %flavour_booleans = map { $_ => 1 } qw(xml_escape);
my %flavour_defaults = (
  theme         => 'default',
  xml_escape    => 1,
);

sub new {
  my $class = shift;
  my %arg = @_;

  # Defaults
  my $self = bless { 
    _file                   => $arg{file} || 
      File::Spec->catfile($Bin, File::Spec->updir, 'config', 'statik.conf'),
    blog_language           => 'en',
    blog_encoding           => 'utf-8',
    post_dir                => 'posts',
    static_dir              => 'static',
    state_dir               => 'state',
    posts_per_page          => 20,
    max_pages               => 1,
    show_future_entries     => 0,
    file_extension          => 'txt',
    show_future_entries     => 0,
    plugin_list             => 'config/plugins.conf',
    index_flavours          => 'html,atom',
  }, $class;
  $self->{_file} = realpath($self->{_file});

  -f $self->{_file}
    or die "Config file '$self->{_file}' not found\n";
  $self->{_config} = Config::Tiny->read( $self->{_file} )
    or die "Read of '$self->{_file} failed\n";

  # Promote all _config->{_} keys to top-level
  my $encoding = $self->{_config}->{_}->{blog_encoding} || $self->{blog_encoding};
  for (keys %{$self->{_config}->{_}}) {
    if (defined(my $val = delete $self->{_config}->{_}->{$_})) {
      $self->{decode($encoding, $_)} = decode($encoding, $val) if $val ne '';
    }
  }
  delete $self->{_config}->{_};

  $self->_check_required;
  $self->_dequote;
  $self->_split_composites;
  $self->_qualify_paths;
  $self->_map_booleans;
  $self->_clean_flavours;

  $self;
}

# Check all required fields are set
sub _check_required {
  my $self = shift;
  for (@main_required) {
    die "Required config item '$_' is not defined - please set and try again\n"
      if ! defined $self->{$_} || $self->{$_} eq '';
  }
}

# Remove quotes from top- and second-level values
sub _dequote {
  my $self = shift;
  s/^(["'])(.*)\1$/$2/ foreach values %$self;
  for my $section (keys %{$self->{_config}}) {
    s/^(["'])(.*)\1$/$2/ foreach values %{$self->{_config}->{$section}};
  }
}

# Split composite values into arrayrefs
sub _split_composites {
  my $self = shift;

  # Comma-separated composites
  for (qw(index_flavours post_flavours)) {
    $self->{$_} = [ split /\s*,\s*/, $self->{$_} ]
      if defined $self->{$_} && $self->{$_} ne '';
    $self->{$_} ||= [];
  }

  # Path composites
  my $sep = ($^O =~ m/^MSWin/ ? ';' : ':');
  for (qw(plugin_path)) {
    $self->{$_} = [ split /\s*$sep\s*/o, $self->{$_} ]
      if defined $self->{$_} && $self->{$_} ne '';
    $self->{$_} ||= [];
  }
}

# Qualify any relative top-level paths
sub _qualify_paths {
  my $self = shift;

  # Default base_dir to parent directory of config file dir
  $self->{base_dir} ||= realpath(File::Spec->catdir( dirname( $self->{_file} ), File::Spec->updir ));

  for ($self->keys) {
    next unless m/_(dir|list|path)$/;
    next if $_ eq 'base_dir';

    if (ref $self->{$_}) {
      $self->{$_} = File::Spec->rel2abs( $self->{$_}, $self->{base_dir} )
        foreach @{$self->{$_}};
    }

    else {
      $self->{$_} = File::Spec->rel2abs( $self->{$_}, $self->{base_dir} );
    }
  }

  # Derive url_path and blog_id_domain, if not set
  $self->{url} = clean_path($self->{url});
  my $url = URI->new($self->{url});
  $self->{blog_id_domain} ||= $url->host;
  $self->{url_path} ||= clean_path($url->path);
}

# Map boolean strings to ints
sub _map_booleans {
  my $self = shift;
  for (keys %main_booleans) {
    $self->{$_} = 1, next if $self->{$_} =~ m/^(yes|on)/;
    $self->{$_} = 0, next if $self->{$_} =~ m/^(no|off)/;
  }
}

# Clean/standardise flavour configs
sub _clean_flavours {
  my $self = shift;

  for my $key (keys %{$self->{_config}}) {
    next unless $key =~ m/^flavour:(\w+)/;
    my $flavour = $1;
    $self->{_config}->{$key}->{suffix} ||= $flavour;

    my $fconfig = merge($self->{_config}->{$key}, \%flavour_defaults);

    # Convert booleans
    for (keys %flavour_booleans) {
      $fconfig->{$_} = 1, next if $fconfig->{$_} =~ m/^(yes|on)/;
      $fconfig->{$_} = 0, next if $fconfig->{$_} =~ m/^(no|off)/;
    }

    $self->{_config}->{$key} = $fconfig;
  }
}

# Return non-private keys
sub keys {
  my $self = shift;
  grep ! /^_/, keys %$self;
}

# Return a hash/hashref of all non-private keys with scalar values
sub to_stash {
  my $self = shift;
  my %stash = map  { $_ => $self->{$_} }
              grep { ! /^_/ && ! ref $self->{$_} }
              CORE::keys %$self;
  return wantarray ? %stash : \%stash;
}

# Return flavour config
sub flavour {
  my ($self, $flavour) = @_;
  $self->{_config}->{"flavour:$flavour"} ||= { %flavour_defaults };
  return $self->{_config}->{"flavour:$flavour"};
}

# Trivial convert-to-hash
sub TO_JSON {
  my $self = shift;
  return { %$self };
}

1;
