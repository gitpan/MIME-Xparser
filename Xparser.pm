use strict;

# some example, and possibly useful, handlers.

#-----------------------------
package MIME::Xparser::Handler::Echo;
#-----------------------------

# this content handler echoes the data, unaltered

sub new  { my $obj; bless \$obj , 'MIME::Xparser::Handler::Echo' }

sub head { shift; print @_ }
sub neck { shift; print @_ }
sub body { shift; print @_ }
sub boundary { shift; print @_ }

# everything else is handled here
use vars qw($AUTOLOAD);
sub AUTOLOAD { }

#-----------------------------
package MIME::Xparser::Handler::Structure;
#-----------------------------

# this content handler displays the structure of a document

sub new { my $obj=0; bless \$obj , 'MIME::Xparser::Handler::Structure' }

sub boundary { shift; print @_ }

use vars qw($AUTOLOAD );
sub AUTOLOAD 
{   my $obj=shift;

    if ($AUTOLOAD =~ m/start_/)
    {   $AUTOLOAD =~ s/.*://;
        print '  'x$$obj , "$AUTOLOAD @_\n";
        $$obj++;
    }

    elsif ($AUTOLOAD =~ m/end_/)
    {   $AUTOLOAD =~ s/.*://;
        $$obj--;
        print '  'x$$obj , "$AUTOLOAD @_\n";
    }
}


#-----------------------------
package MIME::Xparser;
#-----------------------------
use vars qw($VERSION);

$VERSION = '0.3';

use Carp;

sub new
{   my $class=shift;
    my $handler=shift || 'MIME::Xparser no handler defined';
    return bless {handler=>$handler} , 'MIME::Xparser';
}

sub set_content_handler
{   my $obj = shift;
    ($obj->{handler})=@_;

    # we don't provide any callable routines yet, so leave this out
    # $obj->{handler}->set_parser($obj);

}
# double to prevent warning
*MIME::Xparser::Header::set_content_handler = \&set_content_handler;
*MIME::Xparser::Body::set_content_handler   = \&set_content_handler;
*MIME::Xparser::Header::set_content_handler = \&set_content_handler;
*MIME::Xparser::Body::set_content_handler   = \&set_content_handler;


sub line { croak "MIME::Xparser::line() called but we're not in a document" }

sub start_document
{   
    my $obj     = shift;

    my $msg     = { boundary    => '' ,
                    content_type=> '' ,
                    is_mime     => '' ,
                    state       => 'header',
                    is_message  => 1,
                  };    

    $obj->{ header    } = ''       ;   # saved until complete
    $obj->{ msgs      } = [$msg]   ;   # state of each msg
    $obj->{ any_parts } = 0        ;   # earlier boundaries?
    $obj->{ msg       } = $msg     ;   # current msg

    $obj->{handler}->start_document();
    $obj->{handler}->start_message();
    $obj->{handler}->start_headers();
    return bless $obj , 'MIME::Xparser::Header';

}

sub err_start_document
{   carp "MIME::Xparser::start_document() called while still in a document";
    &start_document;
}
# double to prevent warning
*MIME::Xparser::Header::start_document= \&err_start_document;
*MIME::Xparser::Body::start_document  = \&err_start_document;
*MIME::Xparser::Header::start_document= \&err_start_document;
*MIME::Xparser::Body::start_document  = \&err_start_document;

sub good_end_document
{   
    my $obj     = shift;
    my $handler = $obj->{handler};

    my $depth=@{$obj->{msgs}};
    for (my $i = 0; $i < $depth; $i++)
    {   leave($obj);
        my $tossed = shift @{$obj->{msgs}};
        $obj->{msg} = $obj->{msgs}[0];
    }

    $handler->end_document();
    %$obj=(handler=>$handler);
    return bless $obj , 'MIME::Xparser';
}
# double to prevent warning
*MIME::Xparser::Header::end_document = \&good_end_document;
*MIME::Xparser::Body::end_document   = \&good_end_document;
*MIME::Xparser::Header::end_document = \&good_end_document;
*MIME::Xparser::Body::end_document   = \&good_end_document;

sub end_document
{   carp "MIME::Xparser::end_document() called but not in a document";
    &good_end_document;
}

sub MIME::Xparser::Header::in_document {1}
sub MIME::Xparser::Body::in_document {1}
sub MIME::Xparser::in_document {0}

sub leave
{   my $obj = shift;
    my $state = $obj->{msg}{state};

    #header body preamble part postamble

    if ($state eq 'header')
    {   
        $obj->{handler}->end_headers();
    }

    elsif ($state eq 'body')
    {   
        $obj->{handler}->end_body();
    }

    elsif ($state eq 'preamble')
    {   
        $obj->{handler}->end_preamble();
        $obj->{handler}->end_parts();
    }

    elsif ($state eq 'part')
    {   
        $obj->{handler}->end_part();
        $obj->{handler}->end_parts();
    }

    elsif ($state eq 'postamble')
    {
        $obj->{handler}->end_postamble();
        $obj->{handler}->end_parts();
    }

    $obj->{handler}->end_message() 
        if $obj->{msg}{is_message};
}

# RFC1521 -> token = ASCII except SPACE CTLS tspecials
#   tspecials = ()<>@,;:\"/[]?=
# this is the character class to match a token

my $TOKEN = '['. quotemeta( q[!#$%&'*+-.^_`{|}~] ) . '0-9A-Za-z ^_`{|}~]+' ;
my $COMMENT='\\([^\\)]*\\)';

sub parse_value #( string with value as first thing in it)
{   my ($s) = @_;
    my ($value);

    # this accepts quoted values that cross lines, which are not supposed
    # to happen, but if they do, we accept them, including the breaks

    if ( ($value) = $s =~ m/^\s*"(([^"]|\\")*)/ )
    {   # unescape escaped quotes
        $value =~ s/\\"/"/g;                      
    }

    else
    {   # not quoted, just take first token 
        ($value) = $s =~ m/^\s*($TOKEN)/;
    }

    return $value;
}

sub end_of_part_found
{   my $obj     = shift;
    my ($line)  = @_;

    for (my $depth=0; $depth < @{$obj->{msgs}}; $depth++)
    {   my $msg = $obj->{msgs}[$depth];

        if ($msg->{boundary} and $line =~ m/^--$msg->{boundary}((--)?)/)
        {   # boundary found
            my $last = $1;

            for (my $i = 0; $i < $depth; $i++)
            {   leave($obj);
                my $tossed = shift @{$obj->{msgs}};
                $obj->{any_parts}-- if $tossed->{boundary};
                $obj->{msg} = $obj->{msgs}[0];
            }

            my $state = $obj->{msg}{state};

            if ($state eq 'preamble')
            {   $obj->{handler}->end_preamble();
            }
            
            elsif ($state eq 'part')
            {   
                $obj->{handler}->end_part();
            }

            else
            {   die "Unexpected state: $state, in msg "
                    ,%{$obj->{msg}}
                    ," in obj "
                    ,%{$obj}
                    ,". "
                    ;
            }

            $obj->{handler}->boundary($line);

            if ( $last )
            {   
                $obj->{msg}{state} = 'postamble';
                $obj->{msg}{boundary}='';
                $obj->{any_parts}--;

                $obj->{handler}->start_postamble();

                bless $obj , 'MIME::Xparser::Body';
            }

            else
            {   
                $obj->{msg}{state} = 'part';
                $obj->{handler}->start_part();

                my $msg
                    = { boundary    => '' ,
                        content_type=> '' ,
                        is_mime     => '' ,
                        state       => 'header',
                        is_message  => '',
                    };    
                unshift @{$obj->{msgs}} , $msg;
                $obj->{msg} = $obj->{msgs}[0];

                $obj->{handler}->start_headers();
                bless $obj , 'MIME::Xparser::Header';
            }

            return 1; # end found
        }
    }
    return 0; # end not found
}

sub header
{   my $obj     = shift;
    my $header  = $obj->{header};

#     MIME-Version: 1.0     
#     MIME-Version: 1.0 (produced by MetaSend Vx.x)
#     MIME-Version: (produced by MetaSend Vx.x) 1.0
#     MIME-Version: 1.(produced by MetaSend Vx.x)0

    if ( $header =~ 
         /^MIME-Version: ($COMMENT)*1($COMMENT)*\.($COMMENT)*0\b/i
       )
    {   $obj->{msg}{is_mime} =1;
    }

    elsif ( my ($s) = $header =~ m/^Content-type:\s*(.*)/is)
    {
        my ($content_type) = $s =~ m|^($TOKEN/$TOKEN)|;

        $obj->{msg}{content_type} = $content_type;
        $obj->{msg}{boundary} = '';

        if ($content_type =~ m|^multipart/|i)
        {   
            my ($boundary) = $s =~ m/\bboundary=(.*)/is ;
            $boundary = parse_value( $boundary );
            $boundary = quotemeta( $boundary );
            $obj->{msg}{boundary} = $boundary;
        }

    }
}

sub MIME::Xparser::Header::line
{   my $obj    = shift;
    my ($line) = (@_);

    if ($line =~ /^\r?$/)
    {   
        if ($obj->{header})
        {   header($obj);
            $obj->{handler}->header($obj->{header});
            $obj->{header}='';
        }

        $obj->{handler}->end_headers();
        $obj->{handler}->neck($line);

        if ($obj->{msg}{content_type} =~ m|^message/rfc822$|i)
        {   
            $obj->{msg}{state}='body';

            my $msg
                = { boundary    => '' ,
                    content_type=> '' ,
                    is_mime     => '' ,
                    state       => 'header',
                    is_message  => 1,
                  };    
            unshift @{$obj->{msgs}} , $msg;
            $obj->{msg} = $obj->{msgs}[0];

            $obj->{handler}->start_body();
            $obj->{handler}->start_message();
            $obj->{handler}->start_headers();
        }

#        elsif ($obj->{msg}{content_type} =~ m|^multipart/|i)
        
        elsif ($obj->{msg}{boundary}) # implies multipart
        {
            $obj->{msg}{state} = 'preamble';
            $obj->{any_parts} ++;

            $obj->{handler}->start_parts();
            $obj->{handler}->start_preamble();
            bless $obj , 'MIME::Xparser::Body';
        }

        else
        {   
            $obj->{msg}{state}        = 'body';

            $obj->{handler}->start_body();
            bless $obj , 'MIME::Xparser::Body';
        }

    }

    elsif (/^\s/)
    {
        $obj->{header} .= $line;
    }

    else
    {   
        if ($obj->{header})
        {   header($obj);
            $obj->{handler}->header($obj->{header});
            $obj->{header} = '';
        }

        if ( $line =~ m/^--/ and $obj->{any_parts} )
        {   return if end_of_part_found($obj,$line);
        }

        $obj->{header} = $line;
    }
}


sub MIME::Xparser::Body::line 
{   my $obj    = shift;
    my ($line) = (@_);

    if ( $line =~ m/^--/ and $obj->{any_parts} )
    {
        return if end_of_part_found($obj,$line);
    }

    $obj->{handler}->body($line);

}

1;
__END__

=head1 NAME

MIME::Xparser - A mime parser that is somewhat reminiscent of the 
way SAX parses XML (i.e. it invokes callbacks as things are found).

=head1 SYNOPSIS

  use Your_Content_Handler;
  use MIME::Xparser;

  my $handler = new Your_Content_Handler;
  my $parser  = new MIME::Xparser;

  $parser->set_content_handler($handler);

  $parser->start_document();
  while (<YOUR_FILE>)
  {
      $parser->line($_);
  }
  $parser->end_document();


=head1 DESCRIPTION

A program which wishes to parse a mime document feeds lines of input to
the parser (as shown above).

The parser examines each line fed to it, and invokes a series of 
handler methods (listed below) at the appropriate time.

The handler methods are provided by the handler class, which you must
provide.

Structure methods are used to communicate the structure of the document to
your handler.

Data methods are used to pass the lines of data to your handler.  The data
is not altered.  The data is explicitly categorized via the method invoked to
pass the data, and implicitly categorized by the sequence of structure
calls.

The parser provides no information about the document except the
structure.

It is up to the content handler to save and parse out what ever data it
needs when handling the document.  One utility function is available that
may help.  A later version of this module may provide some additional
assistance, though it will never be the intention of this module to handle
the content of a mime document except as required to find its structure.

As mentioned, you must provide the handler.  The source code includes
several simple handlers at the very top.  The distribution includes two
sample scripts that define handlers and parse data.


=head1 PARSER METHODS

=over 4

=item new [ HANDLER-OBJECT (optional) ]

Returns a parser object.  You can specifiy the handler at this time
if you wish.

=item set_content_handler HANDLER-OBJECT

Sets the content handler to use.  No useful return value.

=item start_document

Tells the parser you are about to start parsing a document.  No useful
return value.

=item end_document

Tells the parser you have finished parsing a document.  No useful
return value.

=item in_document

Returns true between calls to start_document and end_document, false
otherwise.  Useful to see if end_document should be called, which may be
useful if a single parser is being used to scan multiple messages (such as
in a mailbox).

=item line A_STRING__ONE_LOGICAL_LINE


This is used to pass the next line of input to the parser.  The lines do
not need to be terminated with a new line, either CRLF, \n, or anything
else.  Each string is assumed to be a single logical line of input.

No useful return value.

=back

=head1 CALLABLE UTILITY FUNCTIONS 

The following may be useful to a handler.  These are regular subs,
not methods.  They are not exported, so you will need to specify them by
their full name, or import them yourself.

=over 4

=item MIME::Xparser::parse_value STRING

Returns the first value found in the string, either a SINGLE mime token,
or a quoted string.  

A quoted string value does not include the quotes, and escaped quotes
within the value will no longer include the escape character (\).

A token is exactly one token, so (for example) it cannot pull out
something like the mime/type (in a single call) because that is two
tokens.

The string must already have been trimmed so that the desired value is the
first thing in the string.

  E.g.
  
  # a typical header
  $string = "A-typical-Header: something=the-value";

  # get a string that has the desired value at the front
  ($contains_the_value) = $string =~ m/something=(.*)/;

  # and extract that value
  $the_value = MIME::Xparser::parse_value($contains_the_value);


=back


=head1 HANDLER INTERFACE

Your content handler should provide the following methods.
AUTOLOAD can be used to reduce the number of methods required.

All methods receive your handler object, as per any method call.
Additional parameters only are shown.

=head2 STRUCTURE METHODS (no (additional) parameters)

=over 4

=item   start_document  

=item   end_document

=item   start_message   

=item   end_message

=item   start_headers

=item   end_headers

=item   start_body      

=item   end_body

=item   start_parts     

=item   end_parts

=item   start_preamble  

=item   end_preamble

=item   start_part      

=item   end_part

=item   start_postamble 

=item   end_postamble

=back

=head2 DATA METHODS (one parameter received)

The four data methods, header, neck, body, and boundary, receive the
original data unaltered.  I.e. If the strings are echoed as they are
received then the original data will be identically reproduced.

=over 4

=item header one_headers_lines_of_input

The parameter input to the handler is a single string which is the
concatenation of the lines that make up a single header.  

The word header, here, means a single header item, not the entire block of
header lines at the top of a mime entity.

=item neck   null_line

The parameter input to the handler is a single string which is the
null line that seperated the headers from the body.

=item body one_line_from_the_body

The parameter input to the handler is a single string which is a
line of data from the body.

=item boundary a_boundary_line

The parameter input to the handler is a single string which is a
boundary line found between parts.

=back 

=head2 METHOD CALL NESTING

The following tries to indicate the nesting of the calls that your handler
will see.  (1) (2) (3) denotes that one of the indicated sets of calls
will be made in any given situation.

Some methods and sets of methods may be invoked multiple times as
appropriate, but that is not shown.

  start_document 
      start_message 
          start_headers 
              header
          end_headers 
          neck

      (1) start_body 
              body
          end_body 

      (2) start_parts 
              start_preamble 
                  body
              end_preamble 
              boundary
              start_part 
                  start_headers 
                      header
                  end_headers 
                  (1) (2) or (3)
              end_part 
              boundary
              start_postamble 
                  body
              end_postamble 
          end_parts 

      (3) start_body 
              start_message
                  (recursively invoke the calls already shown)
              end_message
          end_body 
      end_message
  end_document 


=head1 VERSION

version 0.3

=head1 EXAMPLE

This example displays the structure of the messages in a mail box file.
it uses one of the provided example content handlers.


  #!/usr/bin/perl

  # usage: this-file an-mbox-file
  use MIME::Xparser;

  my $handler = new MIME::Xparser::Handler::Structure();
  my $parser  = new MIME::Xparser($handler);

  FOR:
  for (;;)
  { 
    while (<>)
    {
        if (m/^From /)
        {   
            $parser->end_document() if $parser->in_document();
            print "\n$_";
            $parser->start_document();
            next FOR;
        }
        $parser->line($_);
    }
    $parser->end_document() if $parser->in_document();
    last;
}    


ALSO

The distribution includes  extract-pl  which extracts attachments
from a mail box file, and  examine-pl  which shows the structure of
a message and a few keys other bits of data.  These illustrate some
uses of the module.

The Xparser.pm module includes two trivial handlers at the top of
the code.  These are both potentially useful and are examples of
simple handlers.

=head1 INSTALL

  perl Makefile.PL
  make
  make test
  make install

Or simply copy the Xparser.pm file into a MIME subdirectory of your perl
@INC path.


=head1 BUGS

MIME-Version is found but not used.

Embedded message/rfc822 parts are parsed whether you want them to
be or not.  (That's not really a bug, and your handler is free to
skip them if it wishes.)

Virtually no assistance is provided for the parsing requirements
that a handler might have.  Again, this is not a bug, though it
might be considered a flaw.

The null-line denoting the end of the headers allows for \r in the
line.  Specifically we test for ^\r?$.  This works well on unix
systems reading data that may have either \n new lines or \CR\LF
(which is the standard for "raw" mail data) but may or may not be
appropriate for other systems.  Therefore this may or may not be a
bug for anyone.

Continuation header lines are joined to the initial header line without
removing the line endings.  This is not a bug itself, since the parser
intends to pass the data unaltered, but it conflicts with the intended
behaviour of the parser when handling lines that have no explicit line
ending characters.  In that case this might cause problems.  The handler
should provide a method to join the header lines together, but that seems
like over kill, so this has simply been left as a potential issue for some
unusual parsing situations.

Others - probably?
       
=cut

=head1 AUTHOR

Malcolm Dew-Jones <yf110@victoria.tc.ca>

