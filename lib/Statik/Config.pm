package Statik::Config;

use strict;
use FindBin qw($Bin);
use Config::Tiny;
use Carp;

sub new {
  my $class = shift;
  my %arg = @_;
  $class = ref $class if ref $class;

  my $self = bless { 
    _file       => $arg{file} || "$Bin/../config/statik.conf",
    post_dir    => "$Bin/../posts",
    static_dir  => "$Bin/../static",
  }, $class;

  -f $self->{_file}
    or die "Config file '$self->{_file}' not found\n";
  $self->{_config} = Config::Tiny->read( $self->{_file} )
    or die "Read of '$self->{_file} failed\n";

  # Promote all _config->{_} keys to top-level
  for (keys %{$self->{_config}->{_}}) {
    $self->{$_} = delete $self->{_config}->{_}->{$_};
  }
  delete $self->{_config}->{_};

  $self;
}

sub keys {
  my $self = shift;
  grep ! /^_/, keys %$self;
}

1;
