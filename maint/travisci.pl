sub {
  my ($yaml) = @_;
  @{ $yaml->{branches}->{only} } = map { ( $_ eq 'build/master' ) ? 'build' : $_ } @{ $yaml->{branches}->{only} };
};
