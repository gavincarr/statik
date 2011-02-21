package Statik::Config;

use strict;
use FindBin qw($Bin);
use Cwd qw(realpath);
use File::Spec;
use File::Basename;
use Config::Tiny;
use Encode qw(decode);
use Hash::Merge qw(merge);

my %main_booleans    = map { $_ => 1 } qw(show_future_entries);
my %flavour_booleans = map { $_ => 1 } qw(xml_escape);
my %flavour_defaults = (
  theme         => 'default',
  xml_escape    => 1,
);

sub new {
  my $class = shift;
  my %arg = @_;
  $class = ref $class if ref $class;

  # Defaults
  my $self = bless { 
    _file                   => $arg{file} || 
      File::Spec->catfile($Bin, File::Spec->updir, 'config', 'statik.conf'),
    blog_language           => 'en',
    blog_encoding           => 'utf-8',
    post_dir                => "posts",
    static_dir              => "static",
    state_dir               => "state",
    index_flavours          => 'html,atom',
    posts_per_page          => 20,
    max_pages               => 1,
    show_future_entries     => 0,
  }, $class;
  $self->{_file} = realpath($self->{_file});

  -f $self->{_file}
    or die "Config file '$self->{_file}' not found\n";
  $self->{_config} = Config::Tiny->read( $self->{_file} )
    or die "Read of '$self->{_file} failed\n";

  # Promote all _config->{_} keys to top-level
  my $encoding = $self->{_config}->{_}->{blog_encoding};
  for (keys %{$self->{_config}->{_}}) {
    if (defined(my $val = delete $self->{_config}->{_}->{$_})) {
      $self->{decode($encoding, $_)} = decode($encoding, $val) if $val ne '';
    }
  }
  delete $self->{_config}->{_};

  $self->_qualify_paths;
  $self->_split_composites;
  $self->_map_booleans;
  $self->_clean_flavours;

  $self;
}

# Qualify any relative top-level paths
sub _qualify_paths {
  my $self = shift;

  # Default base_dir to parent directory of config file dir
  $self->{base_dir} ||= realpath(File::Spec->catdir( dirname( $self->{_file} ), File::Spec->updir ));

  for ($self->keys) {
    next unless m/_(dir|list|path)$/;
    next if $_ eq 'base_dir';

    # For paths, qualify all elements, and store as an arrayref
    if (m/_path$/) {
      my $path = $self->{$_};
      $self->{$_} = [];
      for my $elt (split /[:;]/, $path) {
        push @{$self->{$_}}, File::Spec->rel2abs( $elt, $self->{base_dir} );
      }
    }

    else {
      $self->{$_} = File::Spec->rel2abs( $self->{$_}, $self->{base_dir} );
    }
  }
}

# Split composite values into arrayrefs
sub _split_composites {
  my $self = shift;

  # Comma-separated composites
  for (qw(index_flavours post_flavours)) {
    $self->{$_} = [ split /\s*,\s*/, $self->{$_} ];
  }
}

sub _map_booleans {
  my $self = shift;
  for (keys %main_booleans) {
    $self->{$_} = 1, next if $self->{$_} =~ m/^(yes|on)/;
    $self->{$_} = 0, next if $self->{$_} =~ m/^(no|off)/;
  }
}

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

sub keys {
  my $self = shift;
  grep ! /^_/, keys %$self;
}

# Return a hash/hashref of all non-private keys with scalar values
sub to_stash {
  my $self = shift;
  my %stash = map { $_ => $self->{$_} } grep { ! /^_/ && ! ref $self->{$_} } keys %$self;
  return wantarray ? %stash : \%stash;
}

sub flavour {
  my ($self, $flavour) = @_;
  return $self->{_config}->{"flavour:$flavour"};
}

1;
