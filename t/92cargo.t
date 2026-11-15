# -*- cperl -*-

##
# This test checks setCargo() and getCargo(): a Perl value attached to a
# node lives as long as the node, even when no Perl variable refers to
# the node any more, and is released when the node is freed.

use strict;
use warnings;

use Test::More tests => 33;

use XML::LibXML;

# Counts the destruction of cargo objects
my %destroyed;

{
    package Cargo;

    sub new
    {
        my ($class, $name) = @_;
        return bless { name => $name }, $class;
    }

    sub DESTROY
    {
        my $self = shift;
        $destroyed{ $self->{name} }++;
        return;
    }
}

sub parse
{
    return XML::LibXML->load_xml( string => shift );
}

{
    my $doc = parse('<r><a/><b/></r>');
    my $r   = $doc->documentElement;

    # TEST
    ok( !defined( $r->getCargo ), 'no cargo by default' );

    $r->setCargo('hello');

    # TEST
    is( $r->getCargo, 'hello', 'scalar cargo' );

    my $data = { key => 'value' };
    $r->setCargo($data);

    # TEST
    is( $r->getCargo, $data, 'reference cargo: same referent' );

    $r->setCargo(undef);

    # TEST
    ok( !defined( $r->getCargo ), 'setCargo(undef) removes the cargo' );

    $r->firstChild->setCargo('a-cargo');
    $r->lastChild->setCargo('b-cargo');

    # TEST
    is( $r->firstChild->getCargo, 'a-cargo', 'cargo of first child' );

    # TEST
    is( $r->lastChild->getCargo, 'b-cargo', 'cargo of last child' );

    # TEST
    ok( !defined( $r->getCargo ), 'cargo is per node' );
}

# Cargo outlives all Perl references to the node
{
    my $doc = parse('<r><a><b/></a>text</r>');

    $doc->documentElement->firstChild->setCargo('a');
    $doc->findnodes('//b')->[0]->setCargo( [ 1, 2 ] );
    $doc->documentElement->lastChild->setCargo('text');
    $doc->documentElement->setCargo('root');

    # TEST
    is( $doc->documentElement->firstChild->getCargo, 'a',
        'cargo of an element after re-wrapping' );

    # TEST
    is_deeply( $doc->findnodes('//b')->[0]->getCargo, [ 1, 2 ],
        'cargo of a deep element found by XPath' );

    # TEST
    is( $doc->documentElement->lastChild->getCargo, 'text',
        'cargo of a text node' );

    # TEST
    is( $doc->documentElement->getCargo, 'root',
        'cargo of the document element' );

    my $b = $doc->findnodes('//b')->[0];
    my $c = $b->getCargo;
    push @$c, 3;
    undef $b;

    # TEST
    is_deeply( $doc->findnodes('//b')->[0]->getCargo, [ 1, 2, 3 ],
        'cargo is shared, not copied' );
}

# Cargo of attributes
{
    my $doc = parse('<r x="1" y="2"/>');
    $doc->documentElement->getAttributeNode('x')->setCargo('x-cargo');

    # TEST
    is( $doc->documentElement->getAttributeNode('x')->getCargo, 'x-cargo',
        'cargo of an attribute' );

    $doc->documentElement->getAttributeNode('y')->setCargo( Cargo->new('y') );
    $doc->documentElement->removeAttribute('y');

    # TEST
    is( $destroyed{y}, 1, 'cargo released when its attribute is removed' );
}

# Cargo is released with the document
{
    my $doc = parse('<r><a><b/></a></r>');
    $doc->setCargo( Cargo->new('doc') );
    $doc->documentElement->setCargo( Cargo->new('root') );
    $doc->findnodes('//b')->[0]->setCargo( Cargo->new('b') );

    # TEST
    ok( !$destroyed{root} && !$destroyed{b} && !$destroyed{doc},
        'cargo alive while the document is' );

    my $a = $doc->documentElement->firstChild;
    undef $doc;

    # TEST
    ok( !$destroyed{root} && !$destroyed{b},
        'cargo alive while a node keeps the document' );

    # TEST
    is( $a->firstChild->getCargo->{name}, 'b',
        'cargo reached from a node that keeps the document' );

    undef $a;

    # TEST
    is( $destroyed{doc}, 1, 'cargo of the document released' );

    # TEST
    is( $destroyed{root}, 1, 'cargo of the root released' );

    # TEST
    is( $destroyed{b}, 1, 'cargo of a deep node released' );
}

# Cargo of a node created without a document tree
{
    my $doc = XML::LibXML::Document->new;
    my $e   = $doc->createElement('e');
    $e->appendChild( $doc->createElement('f') );
    $e->firstChild->setCargo( Cargo->new('f') );

    # TEST
    is( $e->firstChild->getCargo->{name}, 'f', 'cargo in a detached subtree' );

    undef $e;

    # TEST
    is( $destroyed{f}, 1, 'cargo released with a detached subtree' );
}

# Cargo moves with its node
{
    my $doc = parse('<r><a><b/></a></r>');
    $doc->findnodes('//b')->[0]->setCargo( Cargo->new('moved') );

    my $a = $doc->documentElement->removeChild( $doc->documentElement->firstChild );

    # TEST
    is( $a->firstChild->getCargo->{name}, 'moved', 'cargo moves with removeChild' );

    my $other = parse('<s/>');
    $other->documentElement->appendChild( $other->adoptNode($a) );
    undef $a;
    undef $doc;

    # TEST
    ok( !$destroyed{moved}, 'cargo alive in the new document' );

    # TEST
    is( $other->findnodes('//b')->[0]->getCargo->{name}, 'moved',
        'cargo found in the new document' );

    undef $other;

    # TEST
    is( $destroyed{moved}, 1, 'cargo released with the new document' );
}

# Cargo is not copied
{
    my $doc = parse('<r><a/></r>');
    $doc->documentElement->firstChild->setCargo('original');
    my $copy = $doc->documentElement->cloneNode(1);

    # TEST
    ok( !defined( $copy->firstChild->getCargo ), 'cloneNode does not copy cargo' );
}

# Nodes freed by DOM operations release their cargo
{
    my $doc = parse('<r><a/><b/></r>');
    $doc->documentElement->appendChild( $doc->createTextNode('x') );
    $doc->documentElement->appendChild( $doc->createTextNode('y') )
        ->setCargo( Cargo->new('merged') );
    $doc->documentElement->normalize;

    # TEST
    is( $destroyed{merged}, 1, 'cargo released when normalize() merges its text node' );

    # TEST
    is( $doc->documentElement->lastChild->textContent, 'xy', 'text merged' );

    my $attr = $doc->createAttribute( 'x', 'old' );
    $doc->documentElement->setAttributeNode($attr);
    $attr->firstChild->setCargo( Cargo->new('value') );
    $attr->setValue('new');

    # TEST
    is( $destroyed{value}, 1, 'cargo released when setValue() frees the text of an attribute' );
}

# Many nodes
{
    my $doc  = parse( '<r>' . ( '<i/>' x 1000 ) . '</r>' );
    my $n    = 0;
    for my $i ( $doc->findnodes('//i') ) {
        $i->setCargo( Cargo->new( 'many' ) );
        $n++;
    }

    # TEST
    is( $n, 1000, 'cargo set on many nodes' );

    my $count = grep { defined( $_->getCargo ) } $doc->findnodes('//i');

    # TEST
    is( $count, 1000, 'cargo found on many nodes' );

    undef $doc;

    # TEST
    is( $destroyed{many}, 1000, 'cargo of many nodes released' );
}
