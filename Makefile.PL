sub author_tests  { }
sub readme_from   { }
sub auto_set_repository { }

use inc::Module::Install;
perl_version('5.008');
name 'Web-Hippie-ZeroMQ';
all_from 'lib/Web/Hippie/ZeroMQ.pm';
readme_from 'lib/Web/Hippie/ZeroMQ.pm';
build_requires 'Test::More';
test_requires 'Test::Requires';
requires 'Plack';
requires 'AnyMQ::ZeroMQ' => '0.03';
requires 'JSON';
requires 'Web::Hippie';

auto_include_deps;
auto_set_repository;
WriteAll;
