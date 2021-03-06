#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;



{
    package My::Role;
    use Moose::Role;
}
{
    package My::Class;
    use Moose;
    
    ::throws_ok {
        extends 'My::Role';
    } qr/You cannot inherit from a Moose Role \(My\:\:Role\)/, 
    '... this croaks correctly';
}
