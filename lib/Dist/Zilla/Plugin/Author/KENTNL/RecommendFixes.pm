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

sub _relpath {
  my ( $self, @args ) = @_;
  return $self->root->child(@args);
}

sub _assert_path_bad {
  my ( $self, @apath ) = @_;
  my $path = $self->_relpath(@apath);
  return $path if $path->exists;
  $self->_log_bad( $path . ' does not exist' );
  return;
}

sub _assert_path_meh {
  my ( $self, @apath ) = @_;
  my $path = $self->_relpath(@apath);
  return $path if $path->exists;
  $self->_log_meh( $path . ' does not exist' );
  return;
}

sub _assert_nonpath_meh {
  my ( $self, @apath ) = @_;
  my $path = $self->_relpath(@apath);
  return 1 unless $path->exists;
  $self->_log_meh( $path . ' exists' );
  return;
}

lsub root => sub {
  my ($self) = @_;
  return path( $self->zilla->root );
};

lsub git => sub {
  my ($self) = @_;
  return $self->_assert_path_bad('.git');
};

lsub git_config => sub {
  my ($self) = @_;
  return unless $self->git;
  return $self->_assert_path_bad( '.git', 'config' );
};

lsub dist_ini => sub {
  my ($self) = @_;
  return $self->_assert_path_bad('dist.ini');
};

lsub dist_ini_meta => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('dist.ini.meta');
};

lsub weaver_ini => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('weaver.ini');
};

lsub travis_yml => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('.travis.yml');
};

lsub perltidyrc => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('.perltidyrc');
};

lsub gitignore => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('.gitignore');
};

lsub changes => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('Changes');
};

lsub license => sub {
  my ($self) = @_;
  return $self->_assert_path_meh('LICENSE');
};

lsub changes_deps_files => sub { return [qw( Changes.deps Changes.deps.all Changes.deps.dev Changes.deps.all )] };

lsub has_new_changes_deps => sub {
  my ($self) = @_;
  my $ok = 1;
  for my $file ( @{ $self->changes_deps_files } ) {
    $self->_assert_path_meh( 'misc', $file ) or undef $ok;
    $self->_assert_nonpath_meh($file) or undef $ok;
  }
  return $ok;
};

lsub has_new_perlcritic_deps => sub {
  my ($self) = @_;
  my $ok = 1;
  $self->_assert_path_meh( 'misc', 'perlcritic.deps' ) or undef $ok;
  $self->_assert_nonpath_meh('perlcritic.deps') or undef $ok;
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
  return unless $self->git_config;
  if ( grep { $_ =~ /kentfredric/ } $self->root->child( '.git', 'config' )->lines_utf8( { chomp => 1 } ) ) {
    $self->_log_bad('git repo points to kentfredric');
    return;
  }
  return 1;
};

lsub travis_conf_ok => sub {
  my ($self) = @_;
  return unless $self->travis_yml;
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
  return unless $self->dist_ini;
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
  return unless $self->weaver_ini;
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
  return unless $self->dist_ini_meta;
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
