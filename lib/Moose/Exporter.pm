package Moose::Exporter;

use strict;
use warnings;

use Carp qw( confess );
use Class::MOP;
use List::MoreUtils qw( first_index uniq );
use Sub::Exporter;


my %EXPORT_SPEC;

sub setup_import_methods {
    my ( $class, %args ) = @_;

    my $exporting_package = $args{exporting_package} ||= caller();

    my ( $import, $unimport ) = $class->build_import_methods(%args);

    no strict 'refs';
    *{ $exporting_package . '::import' }   = $import;
    *{ $exporting_package . '::unimport' } = $unimport;
}

sub build_import_methods {
    my ( $class, %args ) = @_;

    my $exporting_package = $args{exporting_package} ||= caller();

    $EXPORT_SPEC{$exporting_package} = \%args;

    my @exports_from = $class->_follow_also( $exporting_package );

    my $exports
        = $class->_make_sub_exporter_params( $exporting_package, @exports_from );

    my $exporter = Sub::Exporter::build_exporter(
        {
            exports => $exports,
            groups  => { default => [':all'] }
        }
    );

    # $args{_export_to_main} exists for backwards compat, because
    # Moose::Util::TypeConstraints did export to main (unlike Moose &
    # Moose::Role).
    my $import = $class->_make_import_sub( $exporting_package, $exporter,
        \@exports_from, $args{_export_to_main} );

    my $unimport
        = $class->_make_unimport_sub( $exporting_package, \@exports_from,
        [ keys %{$exports} ] );

    return ( $import, $unimport )
}

{
    my $seen = {};

    sub _follow_also {
        my $class             = shift;
        my $exporting_package = shift;

        local %$seen = ( $exporting_package => 1 );

        return uniq( _follow_also_real($exporting_package) );
    }

    sub _follow_also_real {
        my $exporting_package = shift;

        die "Package in also ($exporting_package) does not seem to use MooseX::Exporter"
            unless exists $EXPORT_SPEC{$exporting_package};

        my $also = $EXPORT_SPEC{$exporting_package}{also};

        return unless defined $also;

        my @also = ref $also ? @{$also} : $also;

        for my $package (@also)
        {
            die "Circular reference in also parameter to MooseX::Exporter between $exporting_package and $package"
                if $seen->{$package};

            $seen->{$package} = 1;
        }

        return @also, map { _follow_also_real($_) } @also;
    }
}

sub _make_sub_exporter_params {
    my $class    = shift;
    my @packages = @_;

    my %exports;

    for my $package (@packages) {
        my $args = $EXPORT_SPEC{$package}
            or die "The $package package does not use Moose::Exporter\n";

        for my $name ( @{ $args->{with_caller} } ) {
            my $sub = do {
                no strict 'refs';
                \&{ $package . '::' . $name };
            };

            $exports{$name} = $class->_make_wrapped_sub(
                $package,
                $name,
                $sub
            );
        }

        for my $name ( @{ $args->{as_is} } ) {
            my $sub;

            if ( ref $name ) {
                $sub  = $name;
                $name = ( Class::MOP::get_code_info($name) )[1];
            }
            else {
                $sub = do {
                    no strict 'refs';
                    \&{ $package . '::' . $name };
                };
            }

            $exports{$name} = sub {$sub};
        }
    }

    return \%exports;
}

{
    # This variable gets closed over in each export _generator_. Then
    # in the generator we grab the value and close over it _again_ in
    # the real export, so it gets captured each time the generator
    # runs.
    #
    # In the meantime, we arrange for the import method we generate to
    # set this variable to the caller each time it is called.
    #
    # This is all a bit confusing, but it works.
    my $CALLER;

    sub _make_wrapped_sub {
        my $class             = shift;
        my $exporting_package = shift;
        my $name              = shift;
        my $sub               = shift;

        # We need to set the package at import time, so that when
        # package Foo imports has(), we capture "Foo" as the
        # package. This lets other packages call Foo::has() and get
        # the right package. This is done for backwards compatibility
        # with existing production code, not because this is a good
        # idea ;)
        return sub {
            my $caller = $CALLER;
            Class::MOP::subname( $exporting_package . '::'
                    . $name => sub { $sub->( $caller, @_ ) } );
        };
    }

    sub _make_import_sub {
        shift;
        my $exporting_package = shift;
        my $exporter          = shift;
        my $exports_from      = shift;
        my $export_to_main    = shift;

        return sub {
            # I think we could use Sub::Exporter's collector feature
            # to do this, but that would be rather gross, since that
            # feature isn't really designed to return a value to the
            # caller of the exporter sub.
            #
            # Also, this makes sure we preserve backwards compat for
            # _get_caller, so it always sees the arguments in the
            # expected order.
            my $traits;
            ($traits, @_) = Moose::Exporter::_strip_traits(@_);

            # Normally we could look at $_[0], but in some weird cases
            # (involving goto &Moose::import), $_[0] ends as something
            # else (like Squirrel).
            my $class = $exporting_package;

            $CALLER = Moose::Exporter::_get_caller(@_);

            # this works because both pragmas set $^H (see perldoc
            # perlvar) which affects the current compilation -
            # i.e. the file who use'd us - which is why we don't need
            # to do anything special to make it affect that file
            # rather than this one (which is already compiled)

            strict->import;
            warnings->import;

            # we should never export to main
            if ( $CALLER eq 'main' && ! $export_to_main ) {
                warn
                    qq{$class does not export its sugar to the 'main' package.\n};
                return;
            }

            my $did_init_meta;
            for my $c ( grep { $_->can('init_meta') } $class, @{$exports_from} ) {

                $c->init_meta( for_class => $CALLER );
                $did_init_meta = 1;
            }

            if ($did_init_meta) {
                _apply_meta_traits( $CALLER, $traits );
            }
            elsif ( $traits && @{$traits} ) {
                confess
                    "Cannot provide traits when $class does not have an init_meta() method";
            }

            goto $exporter;
        };
    }
}

sub _strip_traits {
    my $idx = first_index { $_ eq '-traits' } @_;

    return ( undef, @_ ) unless $idx >= 0 && $#_ >= $idx + 1;

    my $traits = $_[ $idx + 1 ];

    splice @_, $idx, 2;

    $traits = [ $traits ] unless ref $traits;

    return ( $traits, @_ );
}

sub _apply_meta_traits {
    my ( $class, $traits ) = @_;

    return
        unless $traits && @$traits;

    my $meta = $class->meta();

    my $type = ( split /::/, ref $meta )[-1]
        or confess
        'Cannot determine metaclass type for trait application . Meta isa '
        . ref $meta;

    # We can only call does_role() on Moose::Meta::Class objects, and
    # we can only do that on $meta->meta() if it has already had at
    # least one trait applied to it. By default $meta->meta() returns
    # a Class::MOP::Class object (not a Moose::Meta::Class).
    my @traits = grep {
        $meta->meta()->can('does_role')
            ? not $meta->meta()->does_role($_)
            : 1
        }
        map { Moose::Util::resolve_metatrait_alias( $type => $_ ) } @$traits;

    return unless @traits;

    Moose::Util::apply_all_roles_with_method( $meta,
        'apply_to_metaclass_instance', \@traits );
}

sub _get_caller {
    # 1 extra level because it's called by import so there's a layer
    # of indirection
    my $offset = 1;

    return
          ( ref $_[1] && defined $_[1]->{into} ) ? $_[1]->{into}
        : ( ref $_[1] && defined $_[1]->{into_level} )
        ? caller( $offset + $_[1]->{into_level} )
        : caller($offset);
}

sub _make_unimport_sub {
    shift;
    my $exporting_package = shift;
    my $sources           = shift;
    my $keywords          = shift;

    return sub {
        my $caller = scalar caller();
        Moose::Exporter->_remove_keywords(
            $caller,
            [ $exporting_package, @{$sources} ],
            $keywords
        );
    };
}

sub _remove_keywords {
    shift;
    my $package  = shift;
    my $sources  = shift;
    my $keywords = shift;

    my %sources = map { $_ => 1 } @{$sources};

    no strict 'refs';

    # loop through the keywords ...
    foreach my $name ( @{$keywords} ) {

        # if we find one ...
        if ( defined &{ $package . '::' . $name } ) {
            my $keyword = \&{ $package . '::' . $name };

            # make sure it is from us
            my ($pkg_name) = Class::MOP::get_code_info($keyword);
            next unless $sources{$pkg_name};

            # and if it is from us, then undef the slot
            delete ${ $package . '::' }{$name};
        }
    }
}

1;

__END__

=head1 NAME

Moose::Exporter - make an import() and unimport() just like Moose.pm

=head1 SYNOPSIS

  package MyApp::Moose;

  use strict;
  use warnings;

  use Moose ();
  use Moose::Exporter;

  Moose::Exporter->setup_import_methods(
      export => [ 'sugar1', 'sugar2', \&Some::Random::thing ],
      also   => 'Moose',
  );

  # then later ...
  package MyApp::User;

  use MyApp::Moose;

  has 'name';
  sugar1 'do your thing';
  thing;

  no MyApp::Moose;

=head1 DESCRIPTION

This module encapsulates the logic to export sugar functions like
C<Moose.pm>. It does this by building custom C<import> and C<unimport>
methods for your module, based on a spec your provide.

It also lets your "stack" Moose-alike modules so you can export
Moose's sugar as well as your own, along with sugar from any random
C<MooseX> module, as long as they all use C<Moose::Exporter>.

=head1 METHODS

This module provides two public methods:

=head2 Moose::Exporter->setup_import_methods(...)

When you call this method, C<Moose::Exporter> build custom C<import>
and C<unimport> methods for your module. The import method will export
the functions you specify, and you can also tell it to export
functions exported by some other module (like C<Moose.pm>).

The C<unimport> method cleans the callers namespace of all the
exported functions.

This method accepts the following parameters:

=over 4

=item * with_caller => [ ... ]

This a list of function I<names only> to be exported wrapped and then
exported. The wrapper will pass the name of the calling package as the
first argument to the function. Many sugar functions need to know
their caller so they can get the calling package's metaclass object.

=item * as_is => [ ... ]

This a list of function names or sub references to be exported
as-is. You can identify a subroutine by reference, which is handy to
re-export some other module's functions directly by reference
(C<\&Some::Package::function>).

=item * also => $name or \@names

This is a list of modules which contain functions that the caller
wants to export. These modules must also use C<Moose::Exporter>. The
most common use case will be to export the functions from C<Moose.pm>.

C<Moose::Exporter> also makes sure all these functions get removed
when C<unimport> is called.

=back

=head2 Moose::Exporter->build_import_methods(...)

Returns two code refs, one for import and one for unimport.

Used by C<setup_import_methods>.

=head1 IMPORTING AND init_meta

If you want to set an alternative base object class or metaclass
class, simply define an C<init_meta> method in your class. The
C<import> method that C<Moose::Exporter> generates for you will call
this method (if it exists). It will always pass the caller to this
method via the C<for_class> parameter.

Most of the time, your C<init_meta> method will probably just call C<<
Moose->init_meta >> to do the real work:

  sub init_meta {
      shift; # our class name
      return Moose->init_meta( @_, metaclass => 'My::Metaclass' );
  }

=head1 METACLASS TRAITS

The C<import> method generated by C<Moose::Exporter> will allow the
user of your module to specify metaclass traits in a C<-traits>
parameter passed as part of the import:

  use Moose -traits => 'My::Meta::Trait';

  use Moose -traits => [ 'My::Meta::Trait', 'My::Other::Trait' ];

These traits will be applied to the caller's metaclass
instance. Providing traits for an exporting class that does not create
a metaclass for the caller is an error.

=head1 AUTHOR

Dave Rolsky E<lt>autarch@urth.orgE<gt>

This is largely a reworking of code in Moose.pm originally written by
Stevan Little and others.

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut