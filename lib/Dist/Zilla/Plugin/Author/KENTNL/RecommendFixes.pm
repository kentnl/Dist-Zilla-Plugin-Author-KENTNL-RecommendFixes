use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes;

our $VERSION = '0.002004';

# ABSTRACT: Recommend generic changes to the dist.

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

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
  return $self->log( { prefix => _severe('<severe> ') }, _severe(@args) );
}

sub _log_bad {
  my ( $self, @args ) = @_;
  return $self->log( { prefix => _bad('<bad> ') }, _bad(@args) );
}

sub _log_meh {
  my ( $self, @args ) = @_;
  return $self->log( { prefix => _meh('<meh> ') }, _meh(@args) );
}

sub _relpath {
  my ( $self, @args ) = @_;
  return $self->root->child(@args)->relative( $self->root );
}

sub _cb_bad {
  my ( $self, $message ) = @_;
  return sub { my $context = shift; $self->_log_bad( $context . ' ' . $message ); return };
}

sub _cb_meh {
  my ( $self, $message ) = @_;
  return sub { my $context = shift; $self->_log_meh( $context . ' ' . $message ); return };
}

sub _path_or_callback {
  my ( $self, $apath, $callback ) = @_;
  my $path = $self->_relpath( @{$apath} );
  return $path if $path->exists;
  return $callback->($path);
}

sub _path_then_callback {
  my ( $self, $apath, $callback ) = @_;
  my $path = $self->_relpath( @{$apath} );
  return 1 unless $path->exists;
  return $callback->($path);
}

sub _assert_path_bad {
  my ( $self, @apath ) = @_;
  return $self->_path_or_callback( \@apath, $self->_cb_bad('does not exist') );
}

sub _assert_path_meh {
  my ( $self, @apath ) = @_;
  return $self->_path_or_callback( \@apath, $self->_cb_meh('does not exist') );
}

sub _assert_nonpath_meh {
  my ( $self, @apath ) = @_;
  return $self->_path_then_callback( \@apath, $self->_cb_meh('exists') );
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

lsub git => sub { $_[0]->_path_or_callback( ['.git'], $_[0]->_cb_bad('does not exist') ) };
lsub git_config => sub { $_[0]->_path_or_callback( [ '.git', 'config' ], $_[0]->_cb_bad('does not exist') ) };
lsub dist_ini      => sub { $_[0]->_path_or_callback( ['dist.ini'],      $_[0]->_cb_bad('does not exist') ) };
lsub dist_ini_meta => sub { $_[0]->_path_or_callback( ['dist.ini.meta'], $_[0]->_cb_meh('does not exist') ) };
lsub weaver_ini    => sub { $_[0]->_path_or_callback( ['weaver.ini'],    $_[0]->_cb_meh('does not exist') ) };
lsub travis_yml    => sub { $_[0]->_path_or_callback( ['.travis.yml'],   $_[0]->_cb_meh('does not exist') ) };
lsub perltidyrc    => sub { $_[0]->_path_or_callback( ['.perltidyrc'],   $_[0]->_cb_meh('does not exist') ) };
lsub gitignore     => sub { $_[0]->_path_or_callback( ['.gitignore'],    $_[0]->_cb_meh('does not exist') ) };
lsub changes       => sub { $_[0]->_path_or_callback( ['Changes'],       $_[0]->_cb_meh('does not exist') ) };
lsub license       => sub { $_[0]->_path_or_callback( ['LICENSE'],       $_[0]->_cb_meh('does not exist') ) };

lsub changes_deps_files => sub { return [qw( Changes.deps Changes.deps.all Changes.deps.dev Changes.deps.all )] };

lsub perlcritic_gen => sub {
  my ($self) = @_;
  return $self->_path_or_callback([ 'maint', 'perlcritic.rc.gen.pl' ], $_[0]->_cb_meh('does not exist'));
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
    $self->_path_or_callback( ['misc', $file ] => sub {
      my ($path) = shift;
      undef $ok;
      $self->_log_meh($path . ' does not exist');
    });
    $self->_path_then_callback( [ $file ] => sub { 
      my ($path) = shift;
      undef $ok;
      $self->_log_meh($path . ' exists');
    });
  }
  return $ok;
}

sub has_new_perlcritic_deps {
  my ($self) = @_;
  my $ok = 1;
  undef $ok unless $self->_assert_path_meh( 'misc', 'perlcritic.deps' );
  undef $ok unless $self->_assert_nonpath_meh('perlcritic.deps');
  return $ok;
}

sub has_new_perlcritic_gen {
  my ($self) = @_;
  return unless my $file = $self->perlcritic_gen;
  my @lines = $file->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  undef $ok unless $self->_assert_match_meh( \@lines, qr/Path::Tiny/, $file . ' Should use Path::Tiny' );
  undef $ok unless $self->_assert_match_meh( \@lines, qr/\.\/misc/,   $file . ' should write to misc/' );
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
  my $ok   = 1;

  undef $ok unless $self->_assert_dpath_bad( $conf, _matrix_include_env_coverage(), $path . ' should do coverage testing' );

  for my $perl (qw( 5.21 5.20 5.10 )) {
    undef $ok
      unless $self->_assert_dpath_bad( $conf, _matrix_include_perl($perl), $path . ' should test on this version of perl' );
  }
  for my $perl (qw( 5.8 )) {
    undef $ok
      unless $self->_assert_dpath_meh( $conf, _matrix_include_perl($perl), $path . ' should test on this version of perl' );
  }
  for my $perl (qw( 5.19 )) {
    undef $ok
      unless $self->_assert_not_dpath_bad( $conf, _matrix_include_perl($perl),
      $path . ' should not test on this version of perl' );
  }
  for my $perl (qw( 5.18 )) {
    undef $ok
      unless $self->_assert_not_dpath_meh( $conf, _matrix_include_perl($perl),
      $path . ' should not test on this version of perl' );
  }
  undef $ok unless $self->_assert_dpath_bad( $conf, _clone_scripts(), $path . ' should clone travis ci module' );
  for my $branch (qw( master build/master releases )) {
    undef $ok unless $self->_assert_dpath_bad( $conf, _branch_only($branch), $path . ' should test this branch ' );
  }
  return $ok;
}

sub dist_ini_ok {
  my ($self) = @_;
  return unless my $ini = $self->dist_ini;
  my (@lines) = $ini->lines_utf8( { chomp => 1 } );
  my $ok = 1;
  undef $ok unless $self->_assert_match_meh( \@lines, qr/dzil bakeini/, $ini . ' not baked' );
  undef $ok
    unless $self->_assert_match_meh( \@lines, qr/normal_form\s*=\s*numify/, $ini . ' should set numify as normal form' );
  undef $ok unless $self->_assert_match_meh( \@lines, qr/mantissa\s*=\s*6/, $ini . ' should set mantissa = 6' );
  return $ok;
}

sub weaver_ini_ok {
  my ($self) = @_;
  return unless my $weave = $self->weaver_ini;
  my (@lines) = $weave->lines_utf8( { chomp => 1 } );
  return $self->_assert_match_meh( \@lines, qr/-SingleEncoding/, $weave . ' should set -SingleEncoding' );
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
    undef $ok unless $self->_assert_match_meh( \@lines, $re, $dmeta . ' ' . $message );
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
    undef $ok unless $self->_assert_not_dpath_meh( $distmeta, '/prereqs/*/*/' . $bad, 'Try avoid ' . $bad );
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
