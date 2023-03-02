package Clib::strict;

use strict;
#use warnings;
 
sub import {
    # use warnings;
    #${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "\x10\x01\x00\x00\x00\x50\x04\x00\x00\x00\x00\x00\x00\x55\x51\x55\x50\x01";
    ${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55";
    
    $^H |= 0x00000602; # use strict;
    
}
 
sub unimport {
    $^H &= ~0x00000602;
}

1;
__END__
