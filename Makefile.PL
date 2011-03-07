use inc::Module::Install;

abstract        'Statik is a lightweight text-based static blogging engine, inspired by blosxom';
name            'Statik';
all_from        'lib/Statik.pm';
author          'Gavin Carr <gavin@openfusion.com.au>';
perl_version    '5.006';
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

install_script  'bin/statik';
auto_install;

WriteAll;

