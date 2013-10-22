# Testing Util::clean_path

use Test::More;
use File::Basename;
use URI;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Statik::Util qw(clean_path);

my @data = (
  [ 'foo'           => 'foo/' ],
  [ '/foo'          => 'foo/' ],
  [ 'foo/'          => 'foo/' ],
  [ '/foo/'         => 'foo/' ],

  [ 'foo/bar'       => 'foo/bar/' ],
  [ '/foo/bar'      => 'foo/bar/' ],
  [ 'foo/bar/'      => 'foo/bar/' ],
  [ '/foo/bar/'     => 'foo/bar/' ],

  [ 'foo/bar'       => '/foo/bar/',     first => 1 ],
  [ '/foo/bar'      => '/foo/bar/',     first => 1 ],
  [ 'foo/bar/'      => '/foo/bar/',     first => 1 ],
  [ '/foo/bar/'     => '/foo/bar/',     first => 1 ],

  [ '//foo//bar//'  => 'foo/bar/' ],
  [ '//foo//bar//'  => '/foo/bar/',     first => 1 ],

  [ 'http://example.com/foo/bar'       => 'http://example.com/foo/bar/' ],
  [ 'http://example.com//foo/bar'      => 'http://example.com/foo/bar/' ],
  [ 'http://example.com/foo/bar/'      => 'http://example.com/foo/bar/' ],
  [ 'http://example.com//foo/bar/'     => 'http://example.com/foo/bar/' ],
  [ 'http://example.com/foo/bar'       => 'http://example.com/foo/bar/',    first => 1 ],
  [ 'http://example.com//foo/bar'      => 'http://example.com/foo/bar/',    first => 1 ],
  [ 'http://example.com/foo/bar/'      => 'http://example.com/foo/bar/',    first => 1 ],
  [ 'http://example.com//foo/bar/'     => 'http://example.com/foo/bar/',    first => 1 ],

  [ ''              => '' ],
  [ ''              => '/',             first => 1 ],
);

my ($cleaned);

for my $test (@data) {
  my ($path, $expected, @arg) = @$test;
  if ($path =~ m/^http/) {
    my $uri = URI->new($path, 'http');
    $cleaned = clean_path($uri, @arg);
    ok(! ref $cleaned, "clean_path result is not ref: $cleaned");
  }
  else {
    $cleaned = clean_path($path, @arg);
  }
  is($cleaned, $expected, "path '$path' cleaned correctly");
}

done_testing;

