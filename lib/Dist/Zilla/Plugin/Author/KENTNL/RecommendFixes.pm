use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes;

our $VERSION = '0.001002';

# ABSTRACT: Recommend generic changes to the dist.

# AUTHORITY

use Moose qw( with has );
use MooX::Lsub qw( lsub );
use Path::Tiny qw( path );
use YAML::Tiny;
use Data::DPath qw( dpath );

with 'Dist::Zilla::Role::InstallTool';

use Term::ANSIColor qw( colored );

sub _severe { my (@args) = @_; return colored( ['red'],     @args ) }
sub _bad    { my (@args) = @_; return colored( ['magenta'], @args ) }
sub _meh    { my (@args) = @_; return colored( ['yellow'],  @args ) }

sub _log_severe {
  my ( $self, @args ) = @_;
  return $self->log( _severe(@args) );
}

sub _log_bad {
  my ( $self, @args ) = @_;
  return $self->log( _bad(@args) );
}

sub _log_meh {
  my ( $self, @args ) = @_;
  return $self->log( _meh(@args) );
}

lsub root => sub {
  my ($self) = @_;
  return path( $self->zilla->root );
};

lsub has_git => sub {
  my ($self) = @_;
  return 1 if $self->root->child('.git')->exists;
  $self->_log_bad('.git does not exist');
  return;
};

lsub has_git_config => sub {
  my ($self) = @_;
  return unless $self->has_git;
  return 1 if $self->root->child( '.git', 'config' )->exists;
  $self->_log_bad('.git/config does not exist');
  return;
};

lsub has_dist_ini => sub {
  my ($self) = @_;
  return 1 if $self->root->child('dist.ini')->exists;
  $self->_log_bad('dist.ini does not exist');
  return;
};
lsub has_dist_ini_meta => sub {
  my ($self) = @_;
  return 1 if $self->root->child('dist.ini.meta')->exists;
  $self->_log_meh('dist.ini.meta does not exist, dist is not baked');
  return;
};
lsub has_weaver_ini => sub {
  my ($self) = @_;
  return 1 if $self->root->child('weaver.ini')->exists;
  $self->_log_meh('weaver.ini does not exist');
  return;
};

lsub has_travis_yml => sub {
  my ($self) = @_;
  return 1 if $self->root->child('.travis.yml')->exists;
  $self->_log_meh('.travis.yml does not exist');
  return;
};

lsub has_perltidyrc => sub {
  my ($self) = @_;
  return 1 if $self->root->child('.perltidyrc')->exists;
  $self->_log_meh('.perltidyrc does not exist');
  return;
};

lsub has_gitignore => sub {
  my ($self) = @_;
  return 1 if $self->root->child('.gitignore')->exists;
  $self->_log_meh('.gitignore does not exist');
  return;
};

lsub has_changes => sub {
  my ($self) = @_;
  return 1 if $self->root->child('Changes')->exists;
  $self->_log_meh('Changes does not exist');
  return;
};
lsub has_license => sub {
  my ($self) = @_;
  return 1 if $self->root->child('LICENSE')->exists;
  $self->_log_meh('LICENSE does not exist');
  return;
};

lsub has_new_changes_deps => sub {
  my ($self)  = @_;
  my $ok      = 1;
  my @changes = qw( Changes.deps Changes.deps.all Changes.deps.dev Changes.deps.all );
  for my $file ( map { $self->root->child( 'misc', $_ ) } @changes ) {
    next if $file->exists;
    $self->_log_meh( $file . ' does not exist (legacy changes format)' );
    undef $ok;
  }
  for my $file ( map { $self->root->child( $_ ) } @changes ) {
    next unless $file->exists;
    $self->_log_meh( $file . ' exists (legacy changes format)' );
    undef $ok;
  }
  return $ok;
};

lsub has_new_perlcritic_deps => sub {
  my ($self) = @_;
  my $ok = 1;
  for my $file ( map { $self->root->child( 'misc', $_ ) } qw( perlcritic.deps ) ) {
    next if $file->exists;
    $self->_log_meh( $file . ' does not exist (legacy perlcritic deps format)' );
    undef $ok;
  }
  for my $file ( map { $self->root->child($_) } qw( perlcritic.deps ) ) {
    next unless $file->exists;
    $self->_log_meh( $file . ' exists (legacy perlcritic deps format)' );
    undef $ok;
  }
  return $ok;
};

lsub has_new_perlcritic_gen => sub {
  my ($self) = @_;
  my $file = $self->root->child( 'maint', 'perlcritic.rc.gen.pl' );
  if ( not $file->exists ) {
    $self->_log_meh( 'no ' . $file );
    return;
  }
  my @lines = $file->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  if ( not grep { $_ =~ /Path::Tiny/ } @lines ) {
    $self->_log_meh( $file . ' does not use Path::Tiny' );
    undef $ok;
  }
  if ( not grep { $_ =~ /\.\/misc/ } @lines ) {
    $self->_log_meh( $file . ' does not write to misc/ ' );
    undef $ok;
  }
  return $ok;
};

lsub git_repo_notkentfredric => sub {
  my ($self) = @_;
  return unless $self->has_git_config;
  if ( grep { $_ =~ /kentfredric/ } $self->root->child( '.git', 'config' )->lines_utf8( { chomp => 1 } ) ) {
    $self->_log_bad('git repo points to kentfredric');
    return;
  }
  return 1;
};

lsub travis_conf_ok => sub {
  my ($self) = @_;
  return unless $self->has_travis_yml;
  my $data = YAML::Tiny->read( $self->root->child('.travis.yml')->stringify )->[0];
  my $minc = '/matrix/include/*/';
  my $ok   = 1;
  if ( not dpath( $minc . 'env[ value =~ /COVERAGE_TESTING=1/ ]' )->match($data) ) {
    $self->_log_bad('Does not do coverage testing');
    undef $ok;
  }
  for my $perl (qw( 5.21 5.20 5.10 )) {
    if ( not dpath( $minc . 'perl[ value eq "' . $perl . '"]' )->match($data) ) {
      $self->_log_bad( 'Does not test on ' . $perl );
      undef $ok;
    }
  }
  for my $perl (qw( 5.8 )) {
    if ( not dpath( $minc . 'perl[ value eq "' . $perl . '"]' )->match($data) ) {
      $self->_log_meh( 'Does not test on ' . $perl );
      undef $ok;
    }
  }

  for my $perl (qw( 5.19 )) {
    if ( dpath( $minc . 'perl[ value eq "' . $perl . '"]' )->match($data) ) {
      $self->_log_bad( 'Tests on ' . $perl );
      undef $ok;
    }
  }
  for my $perl (qw( 5.18 )) {
    if ( dpath( $minc . 'perl[ value eq "' . $perl . '"]' )->match($data) ) {
      $self->_log_meh( 'Tests on ' . $perl );
      undef $ok;
    }
  }
  if ( not dpath('/before_install/*[ value =~/git clone.*maint-travis-ci/ ]')->match($data) ) {
    $self->_log_bad('Does not clone travis ci module');
    undef $ok;
  }
  for my $branch (qw( master build/master releases )) {
    if ( not dpath( '/branches/only/*[ value eq "' . $branch . '"]' )->match($data) ) {
      $self->_log_bad( 'Does not test branch ' . $branch );
      undef $ok;
    }
  }
  return $ok;
};

lsub dist_ini_ok => sub {
  my ($self) = @_;
  return unless $self->has_dist_ini;
  my (@lines) = $self->root->child('dist.ini')->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  if ( not grep { $_ =~ /dzil bakeini/ } @lines ) {
    $self->_log_meh('dist.ini not baked');
    undef $ok;
  }
  if ( not grep { $_ =~ /normal_form\s*=\s*numify/ } @lines ) {
    $self->_log_meh('dist.ini does not set numify as its normal form');
    undef $ok;
  }
  if ( not grep { $_ =~ /mantissa\s*=\s*6/ } @lines ) {
    $self->_log_meh('dist.ini does set mantissa = 6');
    undef $ok;
  }
  return $ok;
};
lsub weaver_ini_ok => sub {
  my ($self) = @_;
  return unless $self->has_weaver_ini;
  my (@lines) = $self->root->child('weaver.ini')->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  if ( not grep { $_ =~ /-SingleEncoding/ } @lines ) {
    $self->_log_meh('weaver.ini does not set -SingleEncoding');
    undef $ok;
  }
  return $ok;
};
lsub dist_ini_meta_ok => sub {
  my ($self) = @_;
  return unless $self->has_dist_ini_meta;
  my (@lines) = $self->root->child('dist.ini.meta')->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  if ( not grep { $_ =~ /bumpversions\s*=\s*1/ } @lines ) {
    $self->_log_meh('not using bumpversions');
    undef $ok;
  }
  if ( not grep { $_ =~ /toolkit\s*=\s*eumm/ } @lines ) {
    $self->_log_meh('not using eumm');
    undef $ok;
  }
  if ( not grep { $_ =~ /toolkit_hardness\s*=\s*soft/ } @lines ) {
    $self->_log_meh('not using soft dependencies');
    undef $ok;
  }
  if ( not grep { $_ =~ /copyfiles\s*=.*LICENSE/ } @lines ) {
    $self->_log_meh('no copyfiles = LICENSE');
    undef $ok;
  }
  if ( not grep { $_ =~ /srcreadme\s*=.*/ } @lines ) {
    $self->_log_meh('no srcreadme =');
    undef $ok;
  }
};

sub setup_installer {
  my ($self) = @_;
  $self->has_git;
  $self->has_git_config;
  $self->has_dist_ini;
  $self->has_dist_ini_meta;
  $self->has_weaver_ini;
  $self->has_travis_yml;
  $self->has_perltidyrc;
  $self->has_gitignore;
  $self->has_changes;
  $self->has_license;
  $self->has_new_changes_deps;
  $self->has_new_perlcritic_deps;
  $self->has_new_perlcritic_gen;
  $self->git_repo_notkentfredric;
  $self->travis_conf_ok;
  $self->dist_ini_ok;
  $self->dist_ini_meta_ok;
  return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

=head1 DESCRIPTION

Nothing interesting to see here.

This module just informs me during C<dzil build> that a bunch of
changes that I intend to make to multiple modules have not been applied
to the current distribution.

It does this by spewing colored output.

=for Pod::Coverage bad meh setup_installer severe

=cut
