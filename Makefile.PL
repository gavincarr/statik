use inc::Module::Install;

name            'Statik';
all_from        'lib/Statik.pm';
author          q{Gavin Carr <gavin@openfusion.com.au>};
license         'perl';

build_requires  'Test::More' => 0.88;
build_requires  'Test::Differences';

requires        'parent';
requires        'Config::Tiny';
requires        'Encode';
requires        'Exporter::Lite';
requires        'JSON';
requires        'Hash::Merge';
requires        'Text::MicroMason';
requires        'Time::Piece';
requires        'URI';

auto_install;

WriteAll;

