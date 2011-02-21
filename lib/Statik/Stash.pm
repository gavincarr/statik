package Statik::Stash;

use strict;
use Carp;

# In xml_escape mode, we escape the fields here, and any set via 'set'
my @escape_fields = qw(blog_title blog_description url);
my %escape = (
  q(<) => '&lt;',
  q(>) => '&gt;',
  q(&) => '&amp;',
# q(') => '&apos;',
# q(") => '&quot;',
);
my $escape_re = join('|', keys %escape);

sub new {
  my ($class, %arg) = @_;
  my $self = bless {}, $class;

  # Check arguments
  my $config = delete $arg{config} 
    or croak "Required argument 'config' missing";
  $self->{flavour} = delete $arg{flavour} 
    or croak "Required argument 'flavour' missing";
  croak "Invalid arguments: " . join(',', sort keys %arg) if %arg;

  # Initialise
  my $fconfig = $config->flavour($self->{flavour});
  $self->{suffix} = $fconfig->{suffix};
  $self->{_xml_escape} = $fconfig->{xml_escape};

  my %stash = $config->to_stash;
  @$self{ keys %stash } = values %stash;

  if ($self->{_xml_escape}) {
    $self->set($_ => $self->{$_}) foreach @escape_fields;
  }

  $self;
}

# Return the value for $key
sub get {
  my ($self, $key) = @_;
  $self->{key};
}

# Set the value for $key to $value. If xml escaping is turned on, $value
# is xml-escaped, and an additional key "${key}_unesc" is set to the 
# original unescaped value.
sub set {
  my ($self, $key, $value) = @_;
  if ($self->{_xml_escape} && defined $value) {
    $self->{$key . "_unesc"} = $value;
    $value =~ s/($escape_re)/$escape{$1}/g;
    $self->{$key} = $value;
  }
  else {
    $self->{$key} = $value;
  }
}

1;

