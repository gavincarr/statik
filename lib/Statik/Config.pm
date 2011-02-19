package Statik::Config;

use strict;
use FindBin qw($Bin);
use Cwd qw(realpath);
use File::Spec;
use File::Basename;
use Config::Tiny;

sub new {
  my $class = shift;
  my %arg = @_;
  $class = ref $class if ref $class;

  # Defaults
  my $self = bless { 
    _file           => $arg{file} || File::Spec->catfile($Bin, File::Spec->updir, 'config', 'statik.conf'),
    post_dir        => "posts",
    static_dir      => "static",
    state_dir       => "state",
    index_flavours  => 'html,atom',
  }, $class;
  $self->{_file} = realpath($self->{_file});

  -f $self->{_file}
    or die "Config file '$self->{_file}' not found\n";
  $self->{_config} = Config::Tiny->read( $self->{_file} )
    or die "Read of '$self->{_file} failed\n";

  # Promote all _config->{_} keys to top-level
  my $val;
  for (keys %{$self->{_config}->{_}}) {
    if (defined($val = delete $self->{_config}->{_}->{$_})) {
      $self->{$_} = $val if $val ne '';
    }
  }
  delete $self->{_config}->{_};

  $self->_qualify_paths;
  $self->_split_composites;

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

1;
