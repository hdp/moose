#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;

BEGIN {
    use_ok('Moose');           
}

=pod

This test demonstrates that Moose will respect 
a previously set @ISA using use base, and not 
try to add Moose::Object to it. 

However, this is extremely order sensitive as 
this test also demonstrates.

=cut

{
    package Foo;
    use strict;
    use warnings;
    
    sub foo { 'Foo::foo' }
    
    package Bar;
    use strict;
    use warnings;
    
    use base 'Foo';
    
    use Moose;
    
    sub new { (shift)->meta->new_object(@_) }    
    
    package Baz;
    use strict;
    use warnings;
    use Moose;    
    use base 'Foo'; 
}

my $bar = Bar->new;
isa_ok($bar, 'Bar');
isa_ok($bar, 'Foo');
ok(!$bar->isa('Moose::Object'), '... Bar is not Moose::Object subclass');

my $baz = Baz->new;
isa_ok($baz, 'Baz');
isa_ok($baz, 'Foo');
isa_ok($baz, 'Moose::Object');
