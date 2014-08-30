use strict;
use warnings;

use Test::More;
use Dist::Zilla::Util::Test::KENTNL 1.0001002 qw( dztest );
use Test::DZil qw( simple_ini );

# ABSTRACT: basic test

my $ini = simple_ini( ['Author::KENTNL::RecommendFixes'] );
my $dz = dztest();

$dz->add_file( 'dist.ini',                         $ini );
$dz->add_file( 'lib/Dist/Zilla/Plugin/Example.pm', q[] );
$dz->add_file( 't/basic.t',                        q[] );
$dz->add_file( 'maint/perlcritic.rc.gen.pl',       q[] );
$dz->add_file( '.git/config',                      q[] );
$dz->add_file( 'weaver.ini',                       q[] );
$dz->add_file( 'dist.ini.meta',                    q[] );
$dz->add_file( '.mailmap',                         q[] );
$dz->build_ok;
$dz->has_messages(
  [
    [ qr/perltidyrc does not exist/,      'No perltidy' ],
    [ qr/Changes does not exist/,         'No Changes' ],
    [ qr/LICENSE does not exist/,         'No LICENSE' ],
    [ qr/Changes\.deps does not exist/,   'Diff changes' ],
  ]
);

note explain $dz->builder->log_messages;

done_testing;
