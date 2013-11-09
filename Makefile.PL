use inc::Module::Install;

abstract        'Statik is a lightweight text-based static blogging engine, inspired by blosxom';
name            'Statik';
all_from        'lib/Statik.pm';
author          'Gavin Carr <gavin@openfusion.com.au>';
perl_version    '5.006';
license         'perl';

build_requires  'Test::More' => 0.88;
build_requires  'Test::Differences';
build_requires  'Test::Files';

requires        'Config::Tiny';
requires        'DateTime';
requires        'DateTime::Format::Strptime';
requires        'DateTime::Format::RFC3339';
requires        'Encode';
requires        'Exporter::Lite';
requires        'Hash::Merge';
requires        'JSON';
requires        'parent';
requires        'Text::MicroMason';
requires        'URI';

install_script  'bin/statik';
install_share   'themes';

auto_install;

WriteAll;

