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

sub _assert_match_meh {
  my ( $self, $list, $match, $reason ) = @_;
  for my $line ( @{$list} ) {
    return 1 if $line =~ $match;
  }
  $self->_log_meh("does not match $match, $reason");
  return;
}

sub _assert_nonmatch_bad {
  my ( $self, $list, $match, $reason ) = @_;
  for my $line ( @{$list} ) {
    if ( $line =~ $match ) {
      $self->_log_bad("does match $match, $reason");
      return;
    }
  }
  return 1;
}

sub _assert_dpath_bad {
  my ( $self, $data, $path, $reason ) = @_;
  return 1 if dpath($path)->match($data);
  $self->_log_bad("Did not match expression $path, $reason");
  return;
}

sub _assert_not_dpath_bad {
  my ( $self, $data, $path, $reason ) = @_;
  return 1 unless dpath($path)->match($data);
  $self->_log_bad("Did match expression $path, $reason");
  return;
}

sub _assert_dpath_meh {
  my ( $self, $data, $path, $reason ) = @_;
  return 1 if dpath($path)->match($data);
  $self->_log_meh("Did not match expression $path, $reason");
  return;
}

sub _assert_not_dpath_meh {
  my ( $self, $data, $path, $reason ) = @_;
  return 1 unless dpath($path)->match($data);
  $self->_log_meh("Did match expression $path, $reason");
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

lsub perlcritic_gen => sub {
  my ($self) = @_;
  return $self->_assert_path_meh( 'maint', 'perlcritic.rc.gen.pl' );
};

lsub travis_conf => sub {
  my ($self) = @_;
  return unless my $file = $self->travis_yml;
  my ( $r, $ok );
  eval {
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
    $self->_assert_path_meh( 'misc', $file ) or undef $ok;
    $self->_assert_nonpath_meh($file) or undef $ok;
  }
  return $ok;
}

sub has_new_perlcritic_deps {
  my ($self) = @_;
  my $ok = 1;
  $self->_assert_path_meh( 'misc', 'perlcritic.deps' ) or undef $ok;
  $self->_assert_nonpath_meh('perlcritic.deps') or undef $ok;
  return $ok;
}

sub has_new_perlcritic_gen {
  my ($self) = @_;
  return unless my $file = $self->perlcritic_gen;
  my @lines = $file->lines_utf8( { chomp => 1 } );
  my $ok;
  $self->_assert_match_meh( \@lines, qr/Path::Tiny/, $file . ' Should use Path::Tiny' ) or undef $ok;
  $self->_assert_match_meh( \@lines, qr/\.\/misc/,   $file . ' should write to misc/' ) or undef $ok;
  return $ok;
}

sub git_repo_notkentfredric {
  my ($self) = @_;
  return unless my $config = $self->git_config;
  my @lines = $config->lines_utf8( { chomp => 1 } );
  return $self->_assert_nonmatch_bad( \@lines, qr/kentfredric/, $config . ' Should not point to kentfredric' );
}

sub _matrix_include_env_coverage { return '/matrix/include/*/env[ value =~ /COVERAGE_TESTING=1/' }
sub _matrix_include_perl         { my ($perl) = @_; return "/matrix/include/*/perl[ value eq \"$perl\"]"; }
sub _branch_only                 { my ($branch) = @_; return '/branches/only/*[ value eq "' . $branch . '"]' }
sub _clone_scripts               { return '/before_install/*[ value =~/git clone.*maint-travis-ci/ ]' }

sub travis_conf_ok {
  my ($self) = @_;
  return unless my $conf = $self->travis_conf;
  my $path = $self->travis_yml;
  my $minc = '/matrix/include/*/';
  my $ok   = 1;
  $self->_assert_dpath_bad( $conf, _matrix_include_env_coverage(), $path . ' should do coverage testing' )
    or undef $ok;
  for my $perl (qw( 5.21 5.20 5.10 )) {
    $self->_assert_dpath_bad( $conf, _matrix_include_perl($perl), $path . ' should test on this version of perl' );
  }
  for my $perl (qw( 5.8 )) {
    $self->_assert_dpath_meh( $conf, _matrix_include_perl($perl), $path . ' should test on this version of perl' );
  }
  for my $perl (qw( 5.19 )) {
    $self->_assert_not_dpath_bad( $conf, _matrix_include_perl($perl), $path . ' should not test on this version of perl' );
  }
  for my $perl (qw( 5.18 )) {
    $self->_assert_not_dpath_meh( $conf, _matrix_include_perl($perl), $path . ' should not test on this version of perl' );
  }
  $self->_assert_dpath_bad( $conf, _clone_scripts(), $path . ' should clone travis ci module' );
  for my $branch (qw( master build/master releases )) {
    $self->_assert_dpath_bad( $conf, _branch_only($branch), $path . ' should test this branch ' );
  }
  return $ok;
}

sub dist_ini_ok {
  my ($self) = @_;
  return unless my $ini = $self->dist_ini;
  my (@lines) = $ini->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  $self->_assert_match_meh( \@lines, qr/dzil bakeini/,             $ini . ' not baked' )                        or undef $ok;
  $self->_assert_match_meh( \@lines, qr/normal_form\s*=\s*numify/, $ini . ' should set numify as normal form' ) or undef $ok;
  $self->_assert_match_meh( \@lines, qr/mantissa\s*=\s*6/,         $ini . ' should set mantissa = 6' )          or undef $ok;
  return $ok;
}

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
