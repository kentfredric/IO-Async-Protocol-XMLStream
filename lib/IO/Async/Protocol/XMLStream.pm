use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package IO::Async::Protocol::XMLStream;

# ABSTRACT: Respond to XML elements coming off a wire

# AUTHORITY

use parent 'IO::Async::Protocol::Stream';

use XML::LibXML::SAX::ChunkParser;

our $BUGGY_FINISH = !eval { XML::LibXML::SAX::ChunkParser->VERSION('0.0007'); 1 };

sub _init {
  my ($self) = @_;
  $self->SUPER::_init;
  $self->_XMLStream;
  return $self;
}

## no critic (NamingConventions)
sub _XMLStream {
  my ($self) = @_;
  return $self->{XMLStream} if exists $self->{XMLStream};
  $self->{XMLStream} = {};
  $self->{XMLStream}->{Parser} = XML::LibXML::SAX::ChunkParser->new();
  return $self->{XMLStream};
}
## use critic

my @XML_METHODS = qw(
  attlist_decl
  attribute_decl
  characters
  comment
  doctype_decl
  element_decl
  end_cdata
  end_document
  end_dtd
  end_element
  end_entity
  end_prefix_mapping
  entity_decl
  entity_reference
  error
  external_entity_decl
  fatal_error
  ignorable_whitespace
  internal_entity_decl
  notation_decl
  processing_instruction
  resolve_entity
  set_document_locator
  skipped_entity
  start_cdata
  start_document
  start_dtd
  start_element
  start_entity
  start_prefix_mapping
  unparsed_entity_decl
  warning
  xml_decl
);

sub _set_handler {
  my ( $self, $method, $callback ) = @_;
  if ( not defined $callback ) {
    return $self->_clear_handler($method);
  }
  $self->{ 'on_' . $method } = $callback;
  $self->_XMLStream->{Parser}->{Methods}->{$method} = sub {
    my (@args) = @_;
    $self->invoke_event( 'on_' . $method, @args );
  };
  return $self;
}

sub _clear_handler {
  my ( $self, $method ) = @_;
  delete $self->_XMLStream->{Parser}->{Methods}->{$method};
  delete $self->{ 'on_' . $method };
  return $self;
}

sub configure {
  my ( $self, %params ) = @_;
  for my $method (@XML_METHODS) {
    next unless exists $params{ 'on_' . $method };
    my $cb = delete $params{ 'on_' . $method };
    $self->_set_handler( $method, $cb );
  }
  return $self->SUPER::configure(%params);
}

sub _finish {
  my ($self) = @_;
  if ( !$BUGGY_FINISH ) {
    return $self->_XMLStream->{Parser}->finish;
  }
  my $p  = $self->_XMLStream->{Parser};
  my $lp = $p->{ParserOptions}->{LibParser};
  $lp->set_handler($p);
  $p->finish;
  $lp->set_handler(undef);
  return $self;
}

sub on_read {
  my ( $self, $buffref, $eof ) = @_;
  my $text = substr ${$buffref}, 0, length ${$buffref}, q[];

  $self->_XMLStream->{Parser}->parse_chunk($text) if length $text;
  if ($eof) {
    $self->_finish;
  }
  return 0 if $eof;
  return 1;
}

1;
