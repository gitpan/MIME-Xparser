# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use strict;
BEGIN { $^W = 1 }

######################### We start with some black magic to print on failure.

BEGIN { $| = 1; print "1..10\n"; }
my $loaded;
END {print "not ok 1\n" unless $loaded;}
use MIME::Xparser;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

chdir "./t";

for (my $i=2; -e "msg$i" ; $i++)
{

    open CHK , "chk$i" or die "fatal test error: open chk$i: $!";
    my $chk  = do { local $/ = undef; <CHK> };
    close CHK;

    my $parser  = new MIME::Xparser(my $handler = new handler);

    open MSG , "msg$i" or die "fatal test error: open msg$i: $!";
    $parser->start_document();
    
    while (<MSG>)
    {   $parser->line($_);
    }

    $parser->end_document();
    close MSG;

    if ($chk eq $handler->get_it())
    {   print "ok $i\n";
    }else
    {   print "not ok $i\n";
    }

}


package handler;

sub new { my %obj; bless \%obj , 'handler' }

sub header   { my $obj = shift; $obj->{''} .= join '' , @_ }
sub neck     { my $obj = shift; $obj->{''} .= join '' , @_ }
sub boundary { my $obj = shift; $obj->{''} .= join '' , @_ }
sub body     { my $obj = shift; $obj->{''} .= join '' , @_ }

use vars qw($AUTOLOAD );
sub AUTOLOAD 
{   my $obj=shift;

    if ($AUTOLOAD =~ m/start_document/)
    {   
        $obj->{''} = '';
        $obj->{0}  = 0;

    }

    if ($AUTOLOAD =~ m/start_/)
    {   $AUTOLOAD =~ s/.*://;
        $obj->{''} .= (('  'x($obj->{0})) . "$AUTOLOAD @_\n");
        $obj->{0}++;
    }

    elsif ($AUTOLOAD =~ m/end_/)
    {   $AUTOLOAD =~ s/.*://;
        $obj->{0}--;
        $obj->{''} .= (('  'x($obj->{0})) . "$AUTOLOAD @_\n");
    }
}

sub get_it { my $obj = shift; $obj->{''} }
