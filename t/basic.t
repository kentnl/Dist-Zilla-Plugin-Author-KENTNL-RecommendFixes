use strict;
use warnings;

use Test::More;
use Test::DZil qw( simple_ini );

use lib 't/lib';
use dztest;

# ABSTRACT: basic test

my $ini = simple_ini( ['Author::KENTNL::RecommendFixes'] );
my $dz = dztest->new();

$dz->add_file( 'dist.ini', $ini );
$dz->build_ok;
$dz->has_messages(
  [
    [ qr/\.git does not exist/,           'Uninitialized git' ],
    [ qr/dist\.ini\.meta does not exist/, 'Unbaked dist' ],
    [ qr/weaver\.ini does not exist/,     'Ancient Pod::Weaver' ],
    [ qr/travis\.yml does not exist/,     'No travis setup' ],
    [ qr/perltidyrc does not exist/,      'No perltidy' ],
    [ qr/Changes does not exist/,         'No Changes' ],
    [ qr/LICENSE does not exist/,         'No LICENSE' ],
    [ qr/Changes\.deps does not exist/,   'Diff changes' ],
  ]
);

done_testing;
