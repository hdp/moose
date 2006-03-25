#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 16;

BEGIN {
    use_ok('Moose');           
}

{
    package Foo;
    use strict;
    use warnings;
    use Moose;
    
    sub foo { 'Foo::foo(' . (inner() || '') . ')' }
    sub bar { 'Foo::bar(' . (inner() || '') . ')' }    
    sub baz { 'Foo::baz(' . (inner() || '') . ')' }        
    
    package Bar;
    use strict;
    use warnings;
    use Moose;
    
    extends 'Foo';
    
    augment foo => sub { 'Bar::foo(' . (inner() || '') . ')' };   
    augment bar => sub { 'Bar::bar' };       
    
    package Baz;
    use strict;
    use warnings;
    use Moose;
    
    extends 'Bar';
    
    augment foo => sub { 'Baz::foo' }; 
    augment baz => sub { 'Baz::baz' };       

    # this will actually never run, 
    # because Bar::bar does not call inner()
    augment bar => sub { 'Baz::bar' };  
}

my $baz = Baz->new();
isa_ok($baz, 'Baz');
isa_ok($baz, 'Bar');
isa_ok($baz, 'Foo');

is($baz->foo(), 'Foo::foo(Bar::foo(Baz::foo))', '... got the right value from &foo');
is($baz->bar(), 'Foo::bar(Bar::bar)', '... got the right value from &bar');
is($baz->baz(), 'Foo::baz(Baz::baz)', '... got the right value from &baz');

my $bar = Bar->new();
isa_ok($bar, 'Bar');
isa_ok($bar, 'Foo');

is($bar->foo(), 'Foo::foo(Bar::foo())', '... got the right value from &foo');
is($bar->bar(), 'Foo::bar(Bar::bar)', '... got the right value from &bar');
is($bar->baz(), 'Foo::baz()', '... got the right value from &baz');

my $foo = Foo->new();
isa_ok($foo, 'Foo');

is($foo->foo(), 'Foo::foo()', '... got the right value from &foo');
is($foo->bar(), 'Foo::bar()', '... got the right value from &bar');
is($foo->baz(), 'Foo::baz()', '... got the right value from &baz');