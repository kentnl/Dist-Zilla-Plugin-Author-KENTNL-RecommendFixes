use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes;

our $VERSION = '0.003003';

# ABSTRACT: Recommend generic changes to the dist.

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

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
## use critic

sub _rel {
  my ( $self, @args ) = @_;
  return $self->root->child(@args)->relative( $self->root );
}

sub _data {
  my ( $self, $data, $path ) = @_;
  return Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Data->new(
    path   => $path,
    data   => $data,
    logger => sub { shift; $self->log(@_) },
  );
}

lsub _pc => sub {
  my ($self) = @_;

  my $cache = {};

  Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Assertions->new(
    exist => sub {
      if ( path(@_)->exists ) {
        return ( 1, "@_ exists" );
      }
      return ( 0, "@_ does not exist" );
    },
    have_line => sub {
      my ( $path, $regex ) = @_;
      $cache->{$path} ||= do {
        [ path($path)->lines_raw( { chomp => 1 } ) ];
      };
      for my $line ( @{ $cache->{$path} } ) {
        return ( 1, "Has line matching $regex" ) if $line =~ $regex;
      }
      return ( 0, "Does not have line matching $regex" );
    },
    '-handlers' => {
      should => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        if ( not $status ) {
          $self->log("$name: $message");
          return;
        }
        return $slurpy[0];
      },
      should_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        if ( $status ) {
          $self->log("$name: $message");
          return;
        }
        return $slurpy[0];
      },
      must => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        $self->log_fatal("$name: $message") unless $status;
        return $slurpy[0];
      },
      must_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        $self->log_fatal("$name: $message") if $status;
        return $slurpy[0];
      },
    },
  );

};

lsub root => sub { my ($self) = @_; return path( $self->zilla->root ) };

lsub git      => _badly { $_[0]->_pc->should( exist => $_[0]->_rel('.git') ) };
lsub libdir   => _badly { $_[0]->_pc->should( exist => $_[0]->_rel('lib') ) };
lsub dist_ini => _badly { $_[0]->_pc->should( exist => $_[0]->_rel('dist.ini') ) };
lsub git_config     => sub { $_[0]->_pc->should( exist => $_[0]->_rel('.git/config') ) };
lsub dist_ini_meta  => sub { $_[0]->_pc->should( exist => $_[0]->_rel('dist.ini.meta') ) };
lsub weaver_ini     => sub { $_[0]->_pc->should( exist => $_[0]->_rel('weaver.ini') ) };
lsub travis_yml     => sub { $_[0]->_pc->should( exist => $_[0]->_rel('.travis.yml') ) };
lsub perltidyrc     => sub { $_[0]->_pc->should( exist => $_[0]->_rel('.perltidyrc') ) };
lsub gitignore      => sub { $_[0]->_pc->should( exist => $_[0]->_rel('.gitignore') ) };
lsub changes        => sub { $_[0]->_pc->should( exist => $_[0]->_rel('Changes') ) };
lsub license        => sub { $_[0]->_pc->should( exist => $_[0]->_rel('LICENSE') ) };
lsub mailmap        => sub { $_[0]->_pc->should( exist => $_[0]->_rel('.mailmap') ) };
lsub perlcritic_gen => sub { $_[0]->_pc->should( exist => $_[0]->_rel('maint/perlcritic.rc.gen.pl') ) };

lsub tdir => sub { $_[0]->_pc->should( exist => $_[0]->_rel('t') ) };

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
    push @out, $thing;
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
    push @out, $thing;
  }
  if ( not @out ) {
    $self->log( 'Should have tests in ' . $self->tdir );
  }
  return \@out;

};

sub has_new_changes_deps {
  my ($self) = @_;
  my $ok     = 1;
  my $assert = $self->_pc;
  for my $file ( @{ $self->changes_deps_files } ) {
    undef $ok unless $assert->should( exist => $self->_rel( 'misc', $file ) );
    undef $ok unless $assert->should_not( exist => $self->_rel($file) );
  }
  return $ok;
}

sub has_new_perlcritic_deps {
  my ($self) = @_;
  my $ok     = 1;
  my $assert = $self->_pc;
  undef $ok unless $assert->should( exist => $self->_rel( 'misc', 'perlcritic.deps' ) );
  undef $ok unless $assert->should_not( exist => $self->_rel('perlcritic.deps') );
  return $ok;
}

sub has_new_perlcritic_gen {
  my ($self) = @_;
  return unless my $file = $self->perlcritic_gen;
  my $assert = $self->_pc;
  my $ok     = 1;
  undef $ok unless $assert->should( have_line => $file, qr/Path::Tiny/ );
  undef $ok unless $assert->should( have_line => $file, qr/\.\/misc/ );
  return $ok;
}

sub git_repo_notkentfredric {
  my ($self) = @_;
  return unless my $config = $self->git_config;
  return $self->_pc->should_not( have_line => $config, qr/kentfredric/ );
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
  my $assert = $self->_pc;
  my $ok     = 1;
  my (@tests) = ( qr/dzil bakeini/, qr/normal_form\s*=\s*numify/, qr/mantissa\s*=\s*6/, );
  for my $test (@tests) {
    $assert->should( have_line => $ini, $test );
  }
  if ( not $assert->test( have_line => $ini, qr/dzil bakeini/ ) ) {
    if (  ( not $assert->test( have_line => $ini, qr/bumpversions\s*=\s*1/ ) )
      and ( not $assert->test( have_line => $ini, qr/git_versions/ ) ) )
    {
      _is_bad { $self->log( $ini->stringify . ' is unbaked and has Neither bumpversions=1 or git_versions' ) };
    }
  }
  return $ok;
}

sub weaver_ini_ok {
  my ($self) = @_;
  return unless my $weave = $self->weaver_ini;
  return $self->_pc->should( have_line => $weave, qr/-SingleEncoding/, );
}

sub dist_ini_meta_ok {
  my ($self) = @_;
  return unless my $dmeta = $self->dist_ini_meta;
  my $assert = $self->_pc;
  my (@tests) = (
    qr/bumpversions\s*=\s*1/,        qr/toolkit\s*=\s*eumm/,
    qr/toolkit_hardness\s*=\s*soft/, qr/copyfiles\s*=.*LICENSE/,
    qr/srcreadme\s*=.*/,             qr/copyright_holder\s*=.*<[^@]+@[^>]+>/,
  );
  my $ok = 1;
  for my $test (@tests) {
    undef $ok unless $assert->should( have_line => $dmeta, $test );
  }
  for my $test ( qr/author.*=.*kentfredric/, qr/git_versions/ ) {
    undef $ok unless $assert->should_not( have_line => $dmeta, $test );
  }

  if ( not $assert->test( have_line => $dmeta, qr/bumpversions\s*=\s*1/ )
    and ( not $assert->test( have_line => $dmeta, qr/git_versions/ ) ) )
  {
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
    qw( Sub::Name ),                                         # use Sub::Util
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
  return $self->_pc->should( have_line => $mailmap, qr/<kentnl\@cpan.org>.*<kentfredric\@gmail.com>/ );
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
  my $assert = $self->_pc;
  my (@plugins) = grep { $_->stringify =~ /\Alib\/Dist\/Zilla\/Plugin\//msx } @{ $self->libfiles };
  return unless @plugins;
  for my $plugin (@plugins) {
    $assert->should( have_line => $plugin, _plugin_re('Dist+Zilla+Util+ConfigDumper') );
  }
  return unless $self->tdir;
  return unless @{ $self->tfiles };
FIND_DZTEST: {
    for my $tfile ( @{ $self->tfiles } ) {
      if ( $assert->test( have_line => $tfile, qr/dztest/ ) ) {
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

  package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Assertions;
  ## no critic (Moose::ProhibitNewMethod)

  sub new {
    my ( $class, @args ) = @_;
    my $arg_hash = { ( ref $args[0] ? %{ $args[0] } : @args ) };
    my $tests = {};
    for my $key ( grep { $_ !~ /^-/ } keys %{$arg_hash} ) {
      $tests->{$key} = delete $arg_hash->{$key};
    }
    $arg_hash->{'-handlers'} = { %{ $class->_handler_defaults }, %{ $arg_hash->{'-handlers'} || {} } };
    $arg_hash->{'-tests'} = { %{$tests}, %{ $arg_hash->{'-tests'} || {} } };

    return bless $arg_hash, $class;
  }

  sub _handler_defaults {
    return {
      test => sub {
        my ($status) = @_;
        return $status;
      },
      should => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        warn "Assertion < should $name > failed: $message\n" unless $status;
        return @slurpy;
      },
      should_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        warn "Assertion < should_not $name > failed: $message\n" if $status;
        return @slurpy;
      },
      must => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        die "Assertion < must $name > failed: $message\n" unless $status;
        return @slurpy;
      },
      must_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        die "Assertion < must_not $name > failed: $message\n" if $status;
        return @slurpy;
      },
    };
  }

  for my $handler (qw( should must should_not must_not test )) {
    my $code = sub {
      my ( $self, $name, @slurpy ) = @_;
      if ( not exists $self->{'-tests'}->{$name} ) {
        die "INVALID ASSERTION $name\n";
      }
      my ( $status, $message ) = $self->{'-tests'}->{$name}->(@slurpy);
      return $self->{'-handlers'}->{$handler}->( $status, $message, $name, @slurpy );
    };
    {
      no strict 'refs';
      *{ __PACKAGE__ . '::' . $handler } = $code;
    }
  }

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

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes - Recommend generic changes to the dist.

=head1 VERSION

version 0.003003

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
dzil_plugin_check
mailmap_check

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Kent Fredric <kentfredric@gmail.com>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
