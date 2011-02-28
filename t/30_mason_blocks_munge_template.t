# Testing of Statik::Plugin::MasonBlocks

use Test::More;
use Test::Differences;
use File::Basename;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statik::Plugin::MasonBlocks;

my $stash = {
  author_url        => 'http://www.openfusion.net/',
  author_email      => 'gavin@openfusion.net',
  post_author       => 'Gavin Carr',
  post_author_name  => 'G M Carr',
  post_author_url   => 'http://openfusion.net/',
  post_author_email => 'gavin@openfusion.net',
};

(my $data_dir = basename $0) =~ s/^\d+_//;
$data_dir =~ s/\.t$//;
die "Missing data_dir '$data_dir'\n" unless -d $data_dir;

my ($plugin, $template, $expected);
ok($plugin = Statik::Plugin::MasonBlocks->new(config => {}), "plugin instantiated ok");

for my $template_file (glob "$data_dir/*.tmpl") {
  open my $fh, '<', $template_file or die "open of $template_file failed: $!";
  {
    local $/ = undef;
    $template = <$fh>;
    close $fh;
  }

  (my $expected_file = $template_file) =~ s/\.tmpl$/.expected/;
  $expected = '';
  if (-f $expected_file) {
    open $fh, '<', $expected_file or die "open of $expected_file failed: $!";
    {
      local $/ = undef;
      $expected = <$fh>;
      close $fh;
    }
  }

  eval { $plugin->_munge_template(hook => 'post', template => \$template, stash => $stash) };
  if ($expected) {
    if ($@) {
      eq_or_diff($@, $expected, "template " . basename($template_file) . " died ok");
    } 
    else {
      eq_or_diff($template, $expected, "template " . basename($template_file) . " ok");
    }
  }
  else {
    print $@ || $template;
  }
}

done_testing;

