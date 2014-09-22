use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes;

our $VERSION = '0.003005';

# ABSTRACT: Recommend generic changes to the dist.

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Moose qw( with has around );
use MooX::Lsub qw( lsub );
use Path::Tiny qw( path );
use YAML::Tiny;
use Data::DPath qw( dpath );
use constant _CAN_VARIABLE_MAGIC => eval 'require Variable::Magic; require Tie::RefHash::Weak; 1';

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

sub _mk_assertions {
  my ( $self, @args ) = @_;
  return Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes::_Assertions->new(
    @args,
    '-handlers' => {
      should => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        if ( not $status ) {
          $self->log("should $name: $message");
          return;
        }
        return $slurpy[0];
      },
      should_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        if ($status) {
          $self->log("should_not $name: $message");
          return;
        }
        return $slurpy[0];
      },
      must => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        $self->log_fatal("must $name: $message") unless $status;
        return $slurpy[0];
      },
      must_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        $self->log_fatal("must_not $name: $message") if $status;
        return $slurpy[0];
      },
    },
  );
}

has _pc => ( is => ro =>, lazy => 1, builder => '_build__pc' );

sub _mk_cache {
  my %cache;
  if (_CAN_VARIABLE_MAGIC) {
    ## no critic (Miscellanea::ProhibitTies)
    tie %cache, 'Tie::RefHash::Weak';
  }
  return sub {
    return $cache{ \$_[0] } if exists $cache{ \$_[0] };
    return ( $cache{ \$_[0] } = $_[1]->() );
  };
}

sub _build__pc {
  my ($self) = @_;

  my $line_cache = _mk_cache;

  my $get_lines = sub {
    my ($path) = @_;
    return $line_cache->( $path => sub { [ path($path)->lines_raw( { chomp => 1 } ) ] } );
  };

  return $self->_mk_assertions(
    exist => sub {
      if ( path(@_)->exists ) {
        return ( 1, "@_ exists" );
      }
      return ( 0, "@_ does not exist" );
    },
    have_line => sub {
      my ( $path, $regex ) = @_;
      for my $line ( @{ $get_lines->($path) } ) {
        return ( 1, "$path Has line matching $regex" ) if $line =~ $regex;
      }
      return ( 0, "$path Does not have line matching $regex" );
    },
    have_one_of_line => sub {
      my ( $path, @regexs ) = @_;
      my (@rematches);
      for my $line ( @{ $get_lines->($path) } ) {
        for my $re (@regexs) {
          if ( $line =~ $re ) {
            push @rematches, "Has line matching $re";
          }
        }
      }
      if ( not @rematches ) {
        return ( 0, "Does not match at least one of ( @regexs )" );
      }
      if ( @rematches > 1 ) {
        return ( 0, "Matches more than one of ( @rematches )" );
      }
      return ( 1, "Matches only @rematches" );
    },
  );
}

has _dc => ( is => ro =>, lazy => 1, builder => '_build__dc' );

sub _build__dc {
  my ($self) = @_;

  my $yaml_cache = _mk_cache;

  my $get_yaml = sub {
    my ($path) = @_;
    return $yaml_cache->(
      $path => sub {
        my ( $r, $ok );
        ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        eval {
          $r  = YAML::Tiny->read( path($path)->stringify )->[0];
          $ok = 1;
        };
        return $r;
      },
    );
  };

  return $self->_mk_assertions(
    have_dpath => sub {
      my ( $label, $data, $expression ) = @_;
      if ( dpath($expression)->match($data) ) {
        return ( 1, "$label matches $expression" );
      }
      return ( 0, "$label does not match $expression" );

    },
    yaml_have_dpath => sub {
      my ( $yaml_path, $expression ) = @_;
      if ( dpath($expression)->match( $get_yaml->($yaml_path) ) ) {
        return ( 1, "$yaml_path matches $expression" );
      }
      return ( 0, "$yaml_path does not match $expression" );

    },
  );

}

lsub root => sub { my ($self) = @_; return path( $self->zilla->root ) };

my %amap = (
  git            => '.git',
  libdir         => 'lib',
  dist_ini       => 'dist.ini',
  git_config     => '.git/config',
  dist_ini_meta  => 'dist.ini.meta',
  weaver_ini     => 'weaver.ini',
  travis_yml     => '.travis.yml',
  perltidyrc     => '.perltidyrc',
  gitignore      => '.gitignore',
  changes        => 'Changes',
  license        => 'LICENSE',
  mailmap        => '.mailmap',
  perlcritic_gen => 'maint/perlcritic.rc.gen.pl',
);

for my $key (qw( git libdir dist_ini )) {
  my $value = delete $amap{$key};
  lsub $key => _badly { $_[0]->_pc->should( exist => $_[0]->_rel($value) ) };
}
for my $key ( keys %amap ) {
  my $value = $amap{$key};
  lsub $key => sub { $_[0]->_pc->should( exist => $_[0]->_rel($value) ) };
}

lsub tdir => sub { $_[0]->_pc->should( exist => $_[0]->_rel('t') ) };

lsub changes_deps_files => sub { return [qw( Changes.deps Changes.deps.all Changes.deps.dev Changes.deps.all )] };

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
  return unless my $yaml = $self->travis_yml;
  my $assert = $self->_dc;

  my $ok = 1;

  undef $ok unless $assert->should( yaml_have_dpath => $yaml, '/matrix/include/*/env[ value =~ /COVERAGE_TESTING=1/' );

  for my $perl (qw( 5.21 5.20 5.10 )) {
    undef $ok unless $assert->should( yaml_have_dpath => $yaml, _matrix_include_perl($perl) );
  }
  for my $perl (qw( 5.8 )) {
    undef $ok unless $assert->should( yaml_have_dpath => $yaml, _matrix_include_perl($perl) );
  }
  for my $perl (qw( 5.19 )) {
    undef $ok unless _is_bad { $assert->should_not( yaml_have_dpath => $yaml, _matrix_include_perl($perl) ) };
  }
  for my $perl (qw( 5.18 )) {
    undef $ok unless $assert->should_not( yaml_have_dpath => $yaml, _matrix_include_perl($perl) );
  }
  undef $ok
    unless _is_bad { $assert->should( yaml_have_dpath => $yaml, '/before_install/*[ value =~/git clone.*maint-travis-ci/ ]' ) };
  for my $branch (qw( master build/master releases )) {
    undef $ok unless $assert->should( yaml_have_dpath => $yaml, _branch_only($branch) );
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
    _is_bad { $assert->should( have_one_of_line => $ini, qr/bumpversions\s*=\s*1/, qr/git_versions/ ) };
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
  my (@wanted_regex) = (
    qr/bumpversions\s*=\s*1/,        qr/toolkit\s*=\s*eumm/,
    qr/toolkit_hardness\s*=\s*soft/, qr/copyfiles\s*=.*LICENSE/,
    qr/srcreadme\s*=.*/,             qr/copyright_holder\s*=.*<[^@]+@[^>]+>/,
    qr/twitter_extra_hash_tags\s*=\s*#/,
  );
  my (@unwanted_regex) = (
    #
    qr/author.*=.*kentfredric/, qr/git_versions/,    #
    qr/twitter_hash_tags\s*=\s*#perl\s+#cpan\s*/,    #
  );
  my $ok = 1;
  for my $test (@wanted_regex) {
    undef $ok unless $assert->should( have_line => $dmeta, $test );
  }
  for my $test (@unwanted_regex) {
    undef $ok unless $assert->should_not( have_line => $dmeta, $test );
  }

  _is_bad { $assert->should( have_one_of_line => $dmeta, qr/bumpversions\s*=\s*1/, qr/git_versions/ ) };

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
  my $assert = $self->_dc;

  my $ok = 1;
  for my $bad ( @{ $self->unrecommend } ) {
    undef $ok unless $assert->should_not( have_dpath => 'distmeta', $distmeta, '/prereqs/*/*/' . $bad );
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

  use Carp qw( croak carp );

  sub new {
    my ( $class, @args ) = @_;
    my $arg_hash = { ( ref $args[0] ? %{ $args[0] } : @args ) };
    my $tests = {};
    for my $key ( grep { !/^-/ } keys %{$arg_hash} ) {
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
      log => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        carp sprintf 'Assertion < log %s > = %s : %s', $name, ( $status || '0' ), $message;
        return $slurpy[0];
      },
      should => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        carp "Assertion < should $name > failed: $message" unless $status;
        return $slurpy[0];
      },
      should_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        carp "Assertion < should_not $name > failed: $message" if $status;
        return $slurpy[0];
      },
      must => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        croak "Assertion < must $name > failed: $message" unless $status;
        return $slurpy[0];
      },
      must_not => sub {
        my ( $status, $message, $name, @slurpy ) = @_;
        croak "Assertion < must_not $name > failed: $message" if $status;
        return $slurpy[0];
      },
    };
  }

  for my $handler (qw( should must should_not must_not test log )) {
    my $code = sub {
      my ( $self, $name, @slurpy ) = @_;
      if ( not exists $self->{'-tests'}->{$name} ) {
        croak sprintf q[INVALID ASSERTION %s ( avail: %s )], $name, ( join q[,], keys %{ $self->{'-tests'} } );
      }
      my ( $status, $message ) = $self->{'-tests'}->{$name}->(@slurpy);
      return $self->{'-handlers'}->{$handler}->( $status, $message, $name, @slurpy );
    };
    {
      ## no critic (TestingAndDebugging::ProhibitNoStrict])
      no strict 'refs';
      *{ __PACKAGE__ . q[::] . $handler } = $code;
    }
  }

}
1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::KENTNL::RecommendFixes - Recommend generic changes to the dist.

=head1 VERSION

version 0.003005

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
