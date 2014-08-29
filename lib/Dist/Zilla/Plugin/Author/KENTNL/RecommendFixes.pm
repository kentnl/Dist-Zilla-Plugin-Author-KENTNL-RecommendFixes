use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes;

our $VERSION = '0.002004';

# ABSTRACT: Recommend generic changes to the dist.

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Moose qw( with has around );
use MooX::Lsub qw( lsub );
use Path::Tiny qw( path );
use YAML::Tiny;
use Data::DPath qw( dpath );

with 'Dist::Zilla::Role::InstallTool';

{

  package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Path;

  use Moose;
  use overload q[""] => sub { $_[0]->stringify };

  has 'path' => ( isa => 'Path::Tiny', is => 'ro', handles => [ 'exists', 'lines_utf8', 'stringify' ], required => 1 );
  has 'logger' => ( isa => 'CodeRef', is => 'ro', required => 1 );

  sub assert_exists {
    my ( $self, $cb ) = @_;
    return $self if $self->path->exists;
    $cb->( $self->path->stringify . ' does not exist' );
    return;
  }
}
use Term::ANSIColor qw( colored );

around 'log' => sub {
  my ( $orig, $self, @args ) = @_;
  return $self->$orig( map { ref $_ ? $_ : colored( ['yellow'], $_ ) } @args );
};

sub _cb_m {
  my ( $self, $message ) = @_;
  return sub { my $context = shift; $self->log( $context . ' ' . $message ); return };
}

sub _relpath {
  my ( $self, @args ) = @_;
  return Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Path->new(
    path   => $self->root->child(@args)->relative( $self->root ),
    logger => sub { my $self = shift; $self->log(@_) },
  );
}

sub _path_or_callback {
  my ( $self, $apath, $callback ) = @_;
  my $path = $self->_relpath( @{$apath} );
  return $path if $path->exists;
  if ( not ref $callback ) {
    $self->log( $path . ' ' . $callback );
    return;
  }
  return $callback->($path);
}

sub _path_then_callback {
  my ( $self, $apath, $callback ) = @_;
  my $path = $self->_relpath( @{$apath} );
  return 1 unless $path->exists;
  if ( not ref $callback ) {
    $self->log( $path . ' ' . $callback );
    return;
  }
  return $callback->($path);
}

sub _assert_match {
  my ( $self, $list, $match, $reason ) = @_;
  for my $line ( @{$list} ) {
    return 1 if $line =~ $match;
  }
  $self->log("does not match $match, $reason");
  return;
}

sub _assert_nonmatch {
  my ( $self, $list, $match, $reason ) = @_;
  for my $line ( @{$list} ) {
    if ( $line =~ $match ) {
      $self->log("does match $match, $reason");
      return;
    }
  }
  return 1;
}

sub _assert_dpath {
  my ( $self, $data, $path, $reason ) = @_;
  return 1 if dpath($path)->match($data);
  $self->log("Did not match expression $path, $reason");
  return;
}

sub _assert_not_dpath {
  my ( $self, $data, $path, $reason ) = @_;
  return 1 unless dpath($path)->match($data);
  $self->log("Did match expression $path, $reason");
  return;
}

lsub root => sub {
  my ($self) = @_;
  return path( $self->zilla->root );
};

lsub git           => sub { $_[0]->_relpath('.git')->assert_exists(); };
lsub git_config    => sub { $_[0]->_relpath( '.git', 'config' )->assert_exists() };
lsub dist_ini      => sub { $_[0]->_relpath( 'dist.ini' )->assert_exists() };
lsub dist_ini_meta => sub { $_[0]->_relpath( 'dist.ini.meta' )->assert_exists() };
lsub weaver_ini    => sub { $_[0]->_path_or_callback( ['weaver.ini'], 'does not exist' ) };
lsub travis_yml    => sub { $_[0]->_path_or_callback( ['.travis.yml'], 'does not exist' ) };
lsub perltidyrc    => sub { $_[0]->_path_or_callback( ['.perltidyrc'], 'does not exist' ) };
lsub gitignore     => sub { $_[0]->_path_or_callback( ['.gitignore'], 'does not exist' ) };
lsub changes       => sub { $_[0]->_path_or_callback( ['Changes'], 'does not exist' ) };
lsub license       => sub { $_[0]->_path_or_callback( ['LICENSE'], 'does not exist' ) };

lsub changes_deps_files => sub { return [qw( Changes.deps Changes.deps.all Changes.deps.dev Changes.deps.all )] };

lsub perlcritic_gen => sub {
  my ($self) = @_;
  return $self->_path_or_callback( [ 'maint', 'perlcritic.rc.gen.pl' ], 'does not exist' );
};

lsub travis_conf => sub {
  my ($self) = @_;
  return unless my $file = $self->travis_yml;
  my ( $r, $ok );
  return unless eval {
    $r  = YAML::Tiny->read( $file->stringify )->[0];
    $ok = 1;
  };
  return unless $ok;
  return $r;
};

sub has_new_changes_deps {
  my ($self) = @_;
  my $ok = 1;
  for my $file ( @{ $self->changes_deps_files } ) {
    undef $ok unless $self->_path_or_callback( [ 'misc', $file ] => 'does not exist' );
    undef $ok unless $self->_path_then_callback( [$file] => 'exists' );
  }
  return $ok;
}

sub has_new_perlcritic_deps {
  my ($self) = @_;
  my $ok = 1;
  undef $ok unless $self->_path_or_callback( [ 'misc', 'perlcritic.deps' ] => 'does not exist' );
  undef $ok unless $self->_path_then_callback( ['perlcritic.deps'] => 'exists' );
  return $ok;
}

sub has_new_perlcritic_gen {
  my ($self) = @_;
  return unless my $file = $self->perlcritic_gen;
  my @lines = $file->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  undef $ok unless $self->_assert_match( \@lines, qr/Path::Tiny/, $file . ' Should use Path::Tiny' );
  undef $ok unless $self->_assert_match( \@lines, qr/\.\/misc/,   $file . ' should write to misc/' );
  return $ok;
}

sub git_repo_notkentfredric {
  my ($self) = @_;
  return unless my $config = $self->git_config;
  my @lines = $config->lines_utf8( { chomp => 1 } );
  return $self->_assert_nonmatch( \@lines, qr/kentfredric/, $config . ' Should not point to kentfredric' );
}

sub _matrix_include_env_coverage { return '/matrix/include/*/env[ value =~ /COVERAGE_TESTING=1/' }
sub _matrix_include_perl         { my ($perl) = @_; return "/matrix/include/*/perl[ value eq \"$perl\"]"; }
sub _branch_only                 { my ($branch) = @_; return '/branches/only/*[ value eq "' . $branch . '"]' }
sub _clone_scripts               { return '/before_install/*[ value =~/git clone.*maint-travis-ci/ ]' }

sub travis_conf_ok {
  my ($self) = @_;
  return unless my $conf = $self->travis_conf;
  my $path = $self->travis_yml;
  my $ok   = 1;

  undef $ok unless $self->_assert_dpath( $conf, _matrix_include_env_coverage(), $path . ' should do coverage testing' );

  for my $perl (qw( 5.21 5.20 5.10 )) {
    undef $ok
      unless $self->_assert_dpath( $conf, _matrix_include_perl($perl), $path . ' should test on this version of perl' );
  }
  for my $perl (qw( 5.8 )) {
    undef $ok
      unless $self->_assert_dpath( $conf, _matrix_include_perl($perl), $path . ' should test on this version of perl' );
  }
  for my $perl (qw( 5.19 )) {
    undef $ok
      unless $self->_assert_not_dpath( $conf, _matrix_include_perl($perl), $path . ' should not test on this version of perl' );
  }
  for my $perl (qw( 5.18 )) {
    undef $ok
      unless $self->_assert_not_dpath( $conf, _matrix_include_perl($perl), $path . ' should not test on this version of perl' );
  }
  undef $ok unless $self->_assert_dpath( $conf, _clone_scripts(), $path . ' should clone travis ci module' );
  for my $branch (qw( master build/master releases )) {
    undef $ok unless $self->_assert_dpath( $conf, _branch_only($branch), $path . ' should test this branch ' );
  }
  return $ok;
}

sub dist_ini_ok {
  my ($self) = @_;
  return unless my $ini = $self->dist_ini;
  my (@lines) = $ini->lines_utf8( { chomp => 1 } );
  my $ok      = 1;
  my (@tests) = (
    [ qr/dzil bakeini/,             'not baked' ],
    [ qr/normal_form\s*=\s*numify/, 'should set numify as normal form' ],
    [ qr/mantissa\s*=\s*6/,         'should set mantissa = 6' ],
  );
  for my $test (@tests) {
    my ( $re, $message ) = @{$test};
    undef $ok unless $self->_assert_match( \@lines, $re, $ini . ' ' . $message );
  }
  return $ok;
}

sub weaver_ini_ok {
  my ($self) = @_;
  return unless my $weave = $self->weaver_ini;
  my (@lines) = $weave->lines_utf8( { chomp => 1 } );
  return $self->_assert_match( \@lines, qr/-SingleEncoding/, $weave . ' should set -SingleEncoding' );
}

sub dist_ini_meta_ok {
  my ($self) = @_;
  return unless my $dmeta = $self->dist_ini_meta;
  my (@lines) = $dmeta->lines_utf8( { chomp => 1 } );
  my (@tests) = (
    [ qr/author\.*=.*kentfredric/,     'should not author=kentfredric' ],
    [ qr/bumpversions\s*=\s*1/,        'should use bumpversions' ],
    [ qr/toolkit\s*=\s*eumm/,          'should use eumm' ],
    [ qr/toolkit_hardness\s*=\s*soft/, 'should use soft dependencies' ],
    [ qr/copyfiles\s*=.*LICENSE/,      'should copyfiles = LICENSE' ],
    [ qr/srcreadme\s*=.*/,             'should set srcreadme =' ],
  );
  my $ok = 1;
  for my $test (@tests) {
    my ( $re, $message ) = @{$test};
    undef $ok unless $self->_assert_match( \@lines, $re, $dmeta . ' ' . $message );
  }
  return $ok;
}

lsub unrecommend => sub {
  [
    qw( Path::Class Path::Class::File Path::Class::Dir ),    # Path::Tiny preferred
    qw( JSON JSON::XS JSON::Any ),                           # JSON::MaybeXS preferred
    qw( Path::IsDev Path::FindDev ),                         # Ugh, this is such a bad idea
    qw( File::ShareDir::ProjectDistDir ),                    # Whhhy
    qw( File::Find File::Find::Rule ),                       # Path::Iterator::Rule is much better
    qw( Class::Load ),                                       # Module::Runtime preferred
  ];
};

sub avoid_old_modules {
  my ($self) = @_;
  return unless my $distmeta = $self->zilla->distmeta;
  my $ok = 1;
  for my $bad ( @{ $self->unrecommend } ) {
    undef $ok unless $self->_assert_not_dpath( $distmeta, '/prereqs/*/*/' . $bad, 'Try avoid ' . $bad );
  }
  return $ok;
}

sub setup_installer {
  my ($self) = @_;
  $self->git;
  $self->git_config;
  $self->dist_ini;
  $self->dist_ini_meta;
  $self->weaver_ini;
  $self->travis_yml;
  $self->perltidyrc;
  $self->gitignore;
  $self->changes;
  $self->license;
  $self->has_new_changes_deps;
  $self->has_new_perlcritic_deps;
  $self->has_new_perlcritic_gen;
  $self->git_repo_notkentfredric;
  $self->travis_conf_ok;
  $self->dist_ini_ok;
  $self->dist_ini_meta_ok;
  $self->avoid_old_modules;
  return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes - Recommend generic changes to the dist.

=head1 VERSION

version 0.002004

=head1 DESCRIPTION

Nothing interesting to see here.

This module just informs me during C<dzil build> that a bunch of
changes that I intend to make to multiple modules have not been applied
to the current distribution.

It does this by spewing colored output.

=for Pod::Coverage setup_installer dist_ini_meta_ok dist_ini_ok
git_repo_notkentfredric has_new_changes_deps
has_new_perlcritic_deps has_new_perlcritic_gen
travis_conf_ok weaver_ini_ok avoid_old_modules

=head1 AUTHOR

Kent Fredric <kentfredric@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
