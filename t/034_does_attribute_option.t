#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;

BEGIN {
    use_ok('Moose');           
}

{
    package Foo::Role;
    use strict;
    use warnings;
    use Moose::Role;

    # if does() exists on its own, then 
    # we create a type constraint for 
    # it, just as we do for isa()
    has 'bar' => (is => 'rw', does => 'Bar::Role'); 

    package Bar::Role;
    use strict;
    use warnings;
    use Moose::Role;

    # if isa and does appear together, then see if Class->does(Role)
    # if it does work... then the does() check is actually not needed 
    # since the isa() check will imply the does() check    
    has 'foo' => (is => 'rw', isa => 'Foo::Class', does => 'Foo::Role');    
    
    package Foo::Class;
    use strict;
    use warnings;
    use Moose;
    
    with 'Foo::Role';

    package Bar::Class;
    use strict;
    use warnings;
    use Moose;

    with 'Bar::Role';

}

my $foo = Foo::Class->new;
isa_ok($foo, 'Foo::Class');

my $bar = Bar::Class->new;
isa_ok($bar, 'Bar::Class');

lives_ok {
    $foo->bar($bar);
} '... bar passed the type constraint okay';

dies_ok {
    $foo->bar($foo);
} '... foo did not pass the type constraint okay';

lives_ok {
    $bar->foo($foo);
} '... foo passed the type constraint okay';    

# some error conditions

{
    package Baz::Class;
    use strict;
    use warnings;
    use Moose;

    # if isa and does appear together, then see if Class->does(Role)
    # if it does not,.. we have a conflict... so we die loudly
    ::dies_ok {
        has 'foo' => (isa => 'Foo::Class', does => 'Bar::Class');
    } '... cannot have a does() which is not done by the isa()';
}    
    