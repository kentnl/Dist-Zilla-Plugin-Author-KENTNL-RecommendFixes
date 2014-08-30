use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes;

our $VERSION = '0.003001';

# ABSTRACT: Recommend generic changes to the dist.

# AUTHORITY

use Moose qw( with has around );
use MooX::Lsub qw( lsub );
use Path::Tiny qw( path );
use YAML::Tiny;

with 'Dist::Zilla::Role::InstallTool';

use Term::ANSIColor qw( colored );

our $LOG_COLOR = 'yellow';

around 'log' => sub {
  my ( $orig, $self, @args ) = @_;
  return $self->$orig( map { ref $_ ? $_ : colored( [$LOG_COLOR], $_ ) } @args );
};

## no critic (Subroutines::ProhibitSubroutinePrototypes,Subroutines::RequireArgUnpacking,Variables::ProhibitLocalVars)
sub _is_bad(&) { local $LOG_COLOR = 'red'; return $_[0]->() }

sub _badly(&) {
  my $code = shift;
  return sub { local $LOG_COLOR = 'red'; return $code->(@_); };
}

sub _cast_path {
  my ( $self, $path ) = @_;
  return Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Path->new(
    path   => $path,
    logger => sub { shift; $self->log(@_) },
  );
}
## use critic

sub _relpath {
  my ( $self, @args ) = @_;
  return $self->_cast_path( $self->root->child(@args)->relative( $self->root ) );
}

sub _data {
  my ( $self, $data, $path ) = @_;
  return Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Data->new(
    path   => $path,
    data   => $data,
    logger => sub { shift; $self->log(@_) },
  );
}

lsub root => sub { my ($self) = @_; return path( $self->zilla->root ) };

lsub git      => _badly { $_[0]->_relpath('.git')->assert_exists() };
lsub libdir   => _badly { $_[0]->_relpath('lib')->assert_exists() };
lsub dist_ini => _badly { $_[0]->_relpath('dist.ini')->assert_exists() };

lsub git_config => sub { $_[0]->_relpath( '.git', 'config' )->assert_exists() };
lsub dist_ini_meta  => sub { $_[0]->_relpath('dist.ini.meta')->assert_exists() };
lsub weaver_ini     => sub { $_[0]->_relpath('weaver.ini')->assert_exists() };
lsub travis_yml     => sub { $_[0]->_relpath('.travis.yml')->assert_exists() };
lsub perltidyrc     => sub { $_[0]->_relpath('.perltidyrc')->assert_exists() };
lsub gitignore      => sub { $_[0]->_relpath('.gitignore')->assert_exists() };
lsub changes        => sub { $_[0]->_relpath('Changes')->assert_exists() };
lsub license        => sub { $_[0]->_relpath('LICENSE')->assert_exists() };
lsub mailmap        => sub { $_[0]->_relpath('.mailmap')->assert_exists() };
lsub perlcritic_gen => sub { $_[0]->_relpath( 'maint', 'perlcritic.rc.gen.pl' )->assert_exists() };

lsub tdir => sub { $_[0]->_relpath('t')->assert_exists() };

lsub changes_deps_files => sub { return [qw( Changes.deps Changes.deps.all Changes.deps.dev Changes.deps.all )] };

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

lsub libfiles => sub {
  my ($self) = @_;
  return [] unless $self->libdir;
  my @out;
  my $it = $self->libdir->iterator( { recurse => 1 } );
  while ( my $thing = $it->() ) {
    next if -d $thing;
    next unless $thing->basename =~ /\.pm\z/msx;
    push @out, $self->_cast_path($thing);
  }
  if ( not @out ) {
    _is_bad { $self->log( 'Should have modules in ' . $self->libdir ) };
  }

  return \@out;
};
lsub tfiles => sub {
  my ($self) = @_;
  return [] unless $self->tdir;
  my @out;
  my $it = $self->tdir->iterator( { recurse => 1 } );
  while ( my $thing = $it->() ) {
    next if -d $thing;
    next unless $thing->basename =~ /\.t\z/msx;
    push @out, $self->_cast_path($thing);
  }
  if ( not @out ) {
    $self->log( 'Should have tests in ' . $self->tdir );
  }
  return \@out;

};

sub has_new_changes_deps {
  my ($self) = @_;
  my $ok = 1;
  for my $file ( @{ $self->changes_deps_files } ) {
    undef $ok unless $self->_relpath( 'misc', $file )->assert_exists;
    undef $ok unless $self->_relpath($file)->assert_not_exists;
  }
  return $ok;
}

sub has_new_perlcritic_deps {
  my ($self) = @_;
  my $ok = 1;
  undef $ok unless $self->_relpath( 'misc', 'perlcritic.deps' )->assert_exists;
  undef $ok unless $self->_relpath('perlcritic.deps')->assert_not_exists;
  return $ok;
}

sub has_new_perlcritic_gen {
  my ($self) = @_;
  return unless my $file = $self->perlcritic_gen;
  my $ok = 1;
  undef $ok unless $file->assert_has_line(qr/Path::Tiny/);
  undef $ok unless $file->assert_has_line(qr/\.\/misc/);
  return $ok;
}

sub git_repo_notkentfredric {
  my ($self) = @_;
  return unless my $config = $self->git_config;
  return $config->assert_not_has_line(qr/kentfredric/);
}

sub _matrix_include_perl { my ($perl)   = @_; return "/matrix/include/*/perl[ value eq \"$perl\"]"; }
sub _branch_only         { my ($branch) = @_; return '/branches/only/*[ value eq "' . $branch . '"]' }

sub travis_conf_ok {
  my ($self) = @_;
  return unless my $conf = $self->travis_conf;
  my $data = $self->_data( $self->travis_conf, $self->travis_yml . q[] );

  my $ok = 1;

  undef $ok unless $data->assert_dpath('/matrix/include/*/env[ value =~ /COVERAGE_TESTING=1/');

  for my $perl (qw( 5.21 5.20 5.10 )) {
    undef $ok unless $data->assert_dpath( _matrix_include_perl($perl) );
  }
  for my $perl (qw( 5.8 )) {
    undef $ok unless $data->assert_dpath( _matrix_include_perl($perl) );
  }
  for my $perl (qw( 5.19 )) {
    undef $ok unless _is_bad { $data->assert_not_dpath( _matrix_include_perl($perl) ) };
  }
  for my $perl (qw( 5.18 )) {
    undef $ok unless $data->assert_not_dpath( _matrix_include_perl($perl) );
  }
  undef $ok unless _is_bad { $data->assert_dpath('/before_install/*[ value =~/git clone.*maint-travis-ci/ ]') };
  for my $branch (qw( master build/master releases )) {
    undef $ok unless $data->assert_dpath( _branch_only($branch) );
  }
  return $ok;
}

sub dist_ini_ok {
  my ($self) = @_;
  return unless my $ini = $self->dist_ini;
  my $ok = 1;
  my (@tests) = ( qr/dzil bakeini/, qr/normal_form\s*=\s*numify/, qr/mantissa\s*=\s*6/, );
  for my $test (@tests) {
    $ini->assert_has_line($test);
  }
  if ( not $ini->has_line(qr/dzil bakeini/) ) {
    if ( ( not $ini->has_line(qr/bumpversions\s*=\s*1/) ) and ( not $ini->has_line(qr/git_versions/) ) ) {
      _is_bad { $self->log( $ini->stringify . ' is unbaked and has Neither bumpversions=1 or git_versions' ) };
    }
  }
  return $ok;
}

sub weaver_ini_ok {
  my ($self) = @_;
  return unless my $weave = $self->weaver_ini;
  return $weave->assert_has_line( qr/-SingleEncoding/, );
}

sub dist_ini_meta_ok {
  my ($self) = @_;
  return unless my $dmeta = $self->dist_ini_meta;

  my (@tests) = (
    qr/bumpversions\s*=\s*1/, qr/toolkit\s*=\s*eumm/, qr/toolkit_hardness\s*=\s*soft/, qr/copyfiles\s*=.*LICENSE/,
    qr/srcreadme\s*=.*/,
  );
  my $ok = 1;
  for my $test (@tests) {
    undef $ok unless $dmeta->assert_has_line($test);
  }
  for my $test ( qr/author.*=.*kentfredric/, qr/git_versions/ ) {
    undef $ok unless $dmeta->assert_not_has_line($test);
  }
  if ( ( not $dmeta->has_line(qr/bumpversions\s*=\s*1/) ) and ( not $dmeta->has_line(qr/git_versions/) ) ) {
    _is_bad { $self->log( $dmeta->stringify . ' has Neither bumpversions=1 or git_versions' ) };
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
    qw( Readonly ),                                          # use Const::Fast
  ];
};

sub avoid_old_modules {
  my ($self) = @_;
  return unless my $distmeta = $self->zilla->distmeta;
  my $data = $self->_data( $distmeta, 'distmeta' );

  my $ok = 1;
  for my $bad ( @{ $self->unrecommend } ) {
    undef $ok unless $data->assert_not_dpath( '/prereqs/*/*/' . $bad );
  }
  return $ok;
}

sub mailmap_check {
  my ($self) = @_;
  return unless my $mailmap = $self->mailmap;
  return $mailmap->assert_has_line(qr/<kentnl\@cpan.org>.*<kentfredric\@gmail.com>/);
}

# Hack to avoid matching ourselves.
sub _plugin_re {
  my $inpn = shift;
  my $pn = join q[::], split qr/\+/, $inpn;
  return qr/$pn/;
}

sub dzil_plugin_check {
  my ($self) = @_;
  return unless $self->libdir;
  return unless @{ $self->libfiles };
  my (@plugins) = grep { $_->stringify =~ /\Alib\/Dist\/Zilla\/Plugin\//msx } @{ $self->libfiles };
  return unless @plugins;
  for my $plugin (@plugins) {
    $plugin->assert_has_line( _plugin_re('Dist+Zilla+Util+ConfigDumper') );
  }
  return unless $self->tdir;
  return unless @{ $self->tfiles };
FIND_DZTEST: {
    for my $tfile ( @{ $self->tfiles } ) {
      if ( $tfile->has_line(qr/dztest/) ) {
        last FIND_DZTEST;
      }
    }
    $self->log('A test should probably use dztest (Dist::Zilla::Util::Test::KENTNL)');
  }
  return;
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
  $self->mailmap_check;
  $self->dzil_plugin_check;
  return;
}

__PACKAGE__->meta->make_immutable;
no Moose;

## no critic (Modules::ProhibitMultiplePackages)
{

  package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Path;

  use Moose;
  use overload q[""] => sub { $_[0]->stringify };

  has 'path' =>
    ( isa => 'Path::Tiny', is => 'ro', handles => [ 'exists', 'lines_utf8', 'stringify', 'iterator' ], required => 1 );
  has 'logger'            => ( isa => 'CodeRef',  is => 'ro', required   => 1 );
  has '_lines_utf8_cache' => ( isa => 'ArrayRef', is => 'ro', lazy_build => 1 );

  sub _build__lines_utf8_cache {
    my ($self) = @_;
    return [ $self->path->lines_utf8 ];
  }

  sub has_line {
    my ( $self, $regex ) = @_;
    for my $line ( @{ $self->_lines_utf8_cache } ) {
      return 1 if $line =~ $regex;
    }
    return;
  }

  sub assert_exists {
    my ( $self, ) = @_;
    return $self if $self->path->exists;
    $self->logger->( $self, $self->path->stringify . ' does not exist' );
    return;
  }

  sub assert_not_exists {
    my ( $self, ) = @_;
    return 1 unless $self->path->exists;
    $self->logger->( $self, $self->path->stringify . ' exists' );
    return;
  }

  sub assert_has_line {
    my ( $self, $regex, ) = @_;
    return if $self->has_line($regex);
    $self->logger->( $self, $self->path->stringify . ' should match ' . $regex );
    return;
  }

  sub assert_not_has_line {
    my ( $self, $regex, ) = @_;
    return 1 unless $self->has_line($regex);
    $self->logger->( $self, $self->path->stringify . ' should not match ' . $regex );
    return;
  }
  __PACKAGE__->meta->make_immutable;
}
{

  package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Data;
  use Moose qw( has );
  use Data::DPath qw( dpath );
  has 'data'   => ( isa => 'HashRef', is => 'ro', required => 1 );
  has 'logger' => ( isa => 'CodeRef', is => 'ro', required => 1 );
  has 'path'   => ( isa => 'Str',     is => 'ro', required => 1 );

  sub dpath_match {
    my ( $self, $path ) = @_;
    return dpath($path)->match( $self->data );
  }

  sub assert_dpath {
    my ( $self, $path ) = @_;
    return 1 if $self->dpath_match($path);
    $self->logger->( $self, $self->path . ' should match ' . $path );
    return;
  }

  sub assert_not_dpath {
    my ( $self, $path ) = @_;
    return 1 unless $self->dpath_match($path);
    $self->logger->( $self, $self->path . ' should not match ' . $path );
    return;
  }
  __PACKAGE__->meta->make_immutable;
}
1;

=head1 DESCRIPTION

Nothing interesting to see here.

This module just informs me during C<dzil build> that a bunch of
changes that I intend to make to multiple modules have not been applied
to the current distribution.

It does this by spewing colored output.

=begin Pod::Coverage

setup_installer dist_ini_meta_ok dist_ini_ok
git_repo_notkentfredric has_new_changes_deps
has_new_perlcritic_deps has_new_perlcritic_gen
travis_conf_ok weaver_ini_ok avoid_old_modules
dzil_plugin_check
mailmap_check

=end Pod::Coverage

=cut
