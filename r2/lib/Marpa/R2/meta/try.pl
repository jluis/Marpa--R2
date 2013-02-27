#!/usr/bin/perl
# Copyright 2013 Jeffrey Kegler
# This file is part of Marpa::R2.  Marpa::R2 is free software: you can
# redistribute it and/or modify it under the terms of the GNU Lesser
# General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Marpa::R2 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser
# General Public License along with Marpa::R2.  If not, see
# http://www.gnu.org/licenses/.

use 5.010;
use strict;
use warnings;
use English qw( -no_match_vars );
use Data::Dumper;
use Carp;
use Scalar::Util qw(blessed reftype);

# This is a 'meta' tool, so I relax some of the
# restrictions I use to guarantee portability.
use autodie;

# I expect to be run from a subdirectory in the
# development heirarchy
use lib '../../../';
use lib '../../../../blib/arch';
use Marpa::R2;
BEGIN { require './Try.pm'; }

use Getopt::Long;
my $verbose          = 1;
my $help_flag        = 0;
my $scannerless_flag = 1;
my $result           = Getopt::Long::GetOptions(
    'help'      => \$help_flag,
);
die "usage $PROGRAM_NAME [--help] file ...\n" if $help_flag;

package Marpa::R2::Internal::MetaAST;
our $META_AST;
BEGIN { $META_AST = __PACKAGE__; }
use English qw( -no_match_vars );

my $bnf           = do { local $RS = undef; \(<>) };
my $ast_ref =
    Marpa::R2::Scanless::G->_source_to_ast( $bnf );
die "_source_to_ast did not return an AST" if not ref $ast_ref eq 'REF';
my $parse = bless { p_source => $bnf }, $META_AST;
# say "Original AST = \n", Data::Dumper::Dumper($ast_ref);
say "Evaluated AST = \n", Data::Dumper::Dumper(dwim_evaluate(${$ast_ref}, $parse));
say "self object = \n", Data::Dumper::Dumper($parse);

exit 0;

sub dwim_evaluate {
    my ( $value, $parse ) = @_;
    return $value if not defined $value;
    if ( Scalar::Util::blessed($value) ) {
        return $value->evaluate($parse) if $value->can('evaluate');
        return bless [ map { dwim_evaluate( $_, $parse ) } @{$value} ],
            ref $value
            if Scalar::Util::reftype($value) eq 'ARRAY';
        return $value;
    } ## end if ( Scalar::Util::blessed($value) )
    return [ map { dwim_evaluate( $_, $parse ) } @{$value} ]
        if ref $value eq 'ARRAY';
    return $value;
} ## end sub dwim_evaluate

sub sort_bnf {
    my $cmp = $a->{lhs} cmp $b->{lhs};
    return $cmp if $cmp;
    my $a_rhs_length = scalar @{ $a->{rhs} };
    my $b_rhs_length = scalar @{ $b->{rhs} };
    $cmp = $a_rhs_length <=> $b_rhs_length;
    return $cmp if $cmp;
    for my $ix ( 0 .. ($a_rhs_length-1) ) {
        $cmp = $a->{rhs}->[$ix] cmp $b->{rhs}->[$ix];
        return $cmp if $cmp;
    }
    return 0;
} ## end sub sort_bnf

my %cooked_parse_result = (
    is_lexeme         => $ast_ref->{is_lexeme},
    character_classes => $ast_ref->{character_classes}
);
for my $rule_set (qw(lex_rules g1_rules)) {
    my $aoh        = $ast_ref->{$rule_set};
    my $sorted_aoh = [ sort sort_bnf @{$aoh} ];
    $cooked_parse_result{$rule_set} = $sorted_aoh;
}

say "## The code after this line was automatically generated by ",
    $PROGRAM_NAME;
say "## Date: ", scalar localtime();
$Data::Dumper::Sortkeys = 1;
print Data::Dumper->Dump( [ \%cooked_parse_result ], [qw(hashed_metag)] );
say "## The code before this line was automatically generated by ",
    $PROGRAM_NAME;

exit 0;

# Given a scanless recognizer and
# and the start and end positions, return the input string
sub positions_to_string {
    my ( $parse, $start_position, $end_position ) = @_;
    return substr ${ $parse->{p_source} }, $start_position,
        ( $end_position - $start_position );
}

package Marpa::R2::Internal::MetaG::Symbol;

use English qw( -no_match_vars );

# Make the child argument into a symbol, if it is
# not one already
sub evaluate { return $_[0] };
sub new {
    my ( $class, $self, $hide ) = @_;
    return bless { name => ('' . $self), is_hidden => ($hide//0) }, $class if ref $self eq q{};
    return $self;
}

sub to_symbol_list {
    Marpa::R2::Internal::Meta_AST::Symbol_List->new(@_);
}

sub create_internal_symbol {
    my ($parse, $symbol_name) = @_;
    $parse->{needs_symbol}->{$symbol_name} = 1;
    my $symbol = Marpa::R2::Internal::MetaG::Symbol->new($symbol_name);
    return $symbol;
}

# Return the character class symbol name,
# after ensuring everything is set up properly
sub assign_symbol_by_char_class {
    my ( $self, $char_class, $symbol_name ) = @_;

    # default symbol name always start with TWO left square brackets
    $symbol_name //= '[' . $char_class . ']';
    $self->{character_classes} //= {};
    my $cc_hash    = $self->{character_classes};
    my (undef, $symbol) = $cc_hash->{$symbol_name};
    if ( not defined $symbol ) {
        my $regex;
        if ( not defined eval { $regex = qr/$char_class/xms; 1; } ) {
            Carp::croak( 'Bad Character class: ',
                $char_class, "\n", 'Perl said ', $EVAL_ERROR );
        }
        $symbol = create_internal_symbol($self, $symbol_name);
        $cc_hash->{$symbol_name} = [ $regex, $symbol ];
    } ## end if ( not defined $hash_entry )
    return $symbol;
} ## end sub assign_symbol_by_char_class

sub is_symbol { return 1 };
sub name { return $_[0]->{name} }
sub names { return $_[0]->{name} }
sub is_hidden { return $_[0]->{is_hidden} }
sub are_all_hidden { return $_[0]->{is_hidden} }

sub is_lexical { return shift->{is_lexical} // 0 }
sub hidden_set { return shift->{is_hidden} = 1; }
sub lexical_set { return shift->{is_lexical} = 1; }
sub mask { return shift->is_hidden() ? 0 : 1 }

sub symbols { return $_[0]; }
sub symbol_lists { return $_[0]; }

package Marpa::R2::Internal::Meta_AST::Symbol_List;

sub new { my $class = shift; return bless { symbol_lists => [@_] }, $class }
sub is_symbol { return 0 };

sub to_symbol_list { $_[0]; }

sub names {
    return map { $_->names() } @{ shift->{symbol_lists} };
}

sub are_all_hidden {
     $_->is_hidden() || return 0 for @{ shift->{symbol_lists } };
     return 1;
}

sub is_hidden {
    return map { $_->is_hidden() } @{ shift->{symbol_lists } };
}

sub hidden_set {
    $_->hidden_set() for @{ shift->{symbol_lists} };
    return 0;
}

sub is_lexical { return shift->{is_lexical} // 0 }
sub lexical_set { return shift->{is_lexical} = 1; }

sub mask {
    return
        map { $_ ? 0 : 1 } map { $_->is_hidden() } @{ shift->{symbol_lists} };
}

sub symbols {
    return map { $_->symbols() } @{ shift->{symbol_lists} };
}

# The "unflattened" list, which may contain other lists
sub symbol_lists { return @{ shift->{symbol_lists} }; }

package Marpa::R2::Internal::Meta_AST::Proto_Alternative;
# This class is for pieces of RHS alternatives, as they are
# being constructed

our $PROTO_ALTERNATIVE;
BEGIN { $PROTO_ALTERNATIVE = __PACKAGE__; }

sub combine {
    my ( $class, @hashes ) = @_;
    my $self = bless {}, $class;
    for my $hash_to_add (@hashes) {
        for my $key ( keys %{$hash_to_add} ) {
            Marpa::R2::exception(
                'duplicate key in ',
                $PROTO_ALTERNATIVE,
                "::combine(): $key"
            ) if exists $self->{$key};

            $self->{$key} = $hash_to_add->{$key};
        } ## end for my $key ( keys %{$hash_to_add} )
    } ## end for my $hash_to_add (@hashes)
    return $self;
} ## end sub combine

package Marpa::R2::Internal::MetaG_Nodes::kwc_ws_star;
sub evaluate { return create_internal_symbol($_[1], $_[0]->[0]) }
package Marpa::R2::Internal::MetaG_Nodes::kwc_ws_plus;
sub evaluate { return create_internal_symbol($_[1], $_[0]->[0]) }
package Marpa::R2::Internal::MetaG_Nodes::kwc_ws;
sub evaluate { return create_internal_symbol($_[1], $_[0]->[0]) }
package Marpa::R2::Internal::MetaG_Nodes::kwc_any;
sub evaluate {
    my ($values, $parse) = @_;
    return Marpa::R2::Internal::MetaG::Symbol::assign_symbol_by_char_class(
        $parse, '[\p{Cn}\P{Cn}]', $values->[0] );
}

package Marpa::R2::Internal::MetaG_Nodes::single_symbol;
sub evaluate {
my ($self) = @_;
return $self->[2];
}

package Marpa::R2::Internal::MetaG_Nodes::symbol;
sub evaluate {
my ($self) = @_;
return $self->[2];
}
package Marpa::R2::Internal::MetaG_Nodes::symbol_name;
sub evaluate {
my ($self) = @_;
return $self->[2];
}
package Marpa::R2::Internal::MetaG_Nodes::action_name;
sub evaluate {
my ($self) = @_;
return $self->[2];
}

package Marpa::R2::Internal::MetaG_Nodes::character_class;

sub evaluate {
    my ( $values, $parse ) = @_;
    my $symbol =
        Marpa::R2::Internal::MetaG::Symbol::assign_symbol_by_char_class(
        $parse, $values->[0] );
    $symbol->lexical_set();
    return $symbol;
} ## end sub evaluate

package Marpa::R2::Internal::MetaG_Nodes::bare_name;
sub evaluate { return Marpa::R2::Internal::MetaG::Symbol->new( $_[0]->[0] ); }

sub Marpa::R2::Internal::MetaG_Nodes::reserved_blessing_name::name
{ return $_[0]->[0]; }
sub Marpa::R2::Internal::MetaG_Nodes::blessing_name::name
{
my ($self) = @_;
return $self->[2];
}
sub Marpa::R2::Internal::MetaG_Nodes::standard_name::name
{ return $_[0]->[0]; }

sub Marpa::R2::Internal::MetaG_Nodes::op_declare::name {
    my ($values) = @_;
    return $values->[2];
}

package Marpa::R2::Internal::MetaG_Nodes::bracketed_name;

sub evaluate {
    my ($children) = @_;
    my $bracketed_name = $children->[0];

    # normalize whitespace
    $bracketed_name =~ s/\A [<] \s*//xms;
    $bracketed_name =~ s/ \s* [>] \z//xms;
    $bracketed_name =~ s/ \s+ / /gxms;
    return Marpa::R2::Internal::MetaG::Symbol->new($bracketed_name);
} ## end sub evaluate

package Marpa::R2::Internal::MetaG_Nodes::single_quoted_string;

sub evaluate {
    my ($values, $parse ) = @_;
    my $string = $values->[0];
    my @symbols = ();
    for my $char_class ( map { '[' . (quotemeta $_) . ']' } split //xms, substr $string, 1, -1) {
        my $symbol = Marpa::R2::Internal::MetaG::Symbol::assign_symbol_by_char_class(
        $parse, $char_class);
        push @symbols, $symbol;
    }
    my $list = Marpa::R2::Internal::Meta_AST::Symbol_List->new(@symbols);
    $list->lexical_set();
    return $list;
}

package Marpa::R2::Internal::MetaG_Nodes::rhs_primary;

sub evaluate {
    my ( undef, undef, $values, $parse ) = @_;
    my @symbol_lists = map { $_->evaluate($parse) } @{$values};
    return Marpa::R2::Inner::Scanless::Symbol_List->new( @symbol_lists );
}

package Marpa::R2::Internal::MetaG_Nodes::rhs_primary_list;

sub evaluate {
    my ( $values, $parse ) = @_;
    my @symbol_lists = map { $_->evaluate($parse) } @{$values};
    return Marpa::R2::Inner::Scanless::Symbol_List->new( @symbol_lists );
}

package Marpa::R2::Internal::MetaG_Nodes::parenthesized_rhs_primary_list;

sub evaluate {
    my ( $values, $parse ) = @_;
    my @symbol_lists = map { $_->evaluate($parse) } @{$values};
    my $list = Marpa::R2::Inner::Scanless::Symbol_List->new( @symbol_lists);
    $list->hidden_set();
    return $list;
} ## end sub evaluate

package Marpa::R2::Internal::MetaG_Nodes::rhs;

sub evaluate {
    my ( $values, $parse ) = @_;
    my @symbol_lists = map { $_->evaluate($parse) } @{$values};
    my $list = Marpa::R2::Inner::Scanless::Symbol_List->new( @symbol_lists);
    return bless { rhs => $list}, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::action;

sub evaluate {
    my ( $values, $parse ) = @_;
    my (undef, undef, $child) = @{$values};
    return bless { action => $child->evaluate($parse) }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::blessing;

sub evaluate {
    my ( $values ) = @_;
    my (undef, undef, $child) = @{$values};
    return bless { bless => $child->name() }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::right_association;
sub evaluate {
    my ( $values ) = @_;
    return bless { assoc => 'R' }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::left_association;
sub evaluate {
    my ( $values ) = @_;
    return bless { assoc => 'L' }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::group_association;
sub evaluate {
    my ( $values ) = @_;
    return bless { assoc => 'G' }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::proper_specification;
sub evaluate {
    my ( $values ) = @_;
    my $child = $values->[2];
    return bless { proper => $child }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::separator_specification;
sub evaluate {
    my ( $values, $parse ) = @_;
    my $child = $values->[2];
    return bless { separator => $child->evaluate($parse) }, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::adverb_item;
sub evaluate {
    my ( $values, $parse ) = @_;
    my $child = $values->[2]->evaluate($parse);
    return bless $child, $PROTO_ALTERNATIVE;
}

package Marpa::R2::Internal::MetaG_Nodes::adverb_list;
sub evaluate {
    my ( $values, $parse ) = @_;
    my (@adverb_items ) = map { $_->evaluate($parse) } @{$values};
    return Marpa::R2::Internal::Meta_AST::Proto_Alternative->combine( @adverb_items);
}

package Marpa::R2::Internal::MetaG_Nodes::default_rule;
sub evaluate {
    my ( $values, $parse ) = @_;
    my ( undef, undef, undef, $op_declare, $unevaluated_adverb_list ) = @{$values};
    my $grammar_level = $op_declare eq q{::=} ? 1 : 0;
    my $adverb_list = $unevaluated_adverb_list->evaluate();

    # A default rule clears the previous default
    my %default_adverbs = ();
    $parse->{default_adverbs}->[$grammar_level] = \%default_adverbs;

    ADVERB: for my $key ( keys %{$adverb_list} ) {
        my $value = $adverb_list->{$key};
        if ( $key eq 'action' ) {
            $default_adverbs{$key} = $value;
            next ADVERB;
        }
        if ( $key eq 'bless' ) {
            $default_adverbs{$key} = $value;
            next ADVERB;
        }
        Marpa::R2::exception(qq{"$key" adverb not allowed in default rule"});
    } ## end ADVERB: for my $key ( keys %{$adverb_list} )
    return undef;
} ## end sub evaluate

package Marpa::R2::Internal::MetaG_Nodes::lexeme_rule;
sub evaluate {
    my ( $values, $parse ) = @_;
    my ( $start, $end, undef, $op_declare, $unevaluated_adverb_list ) =
        @{$values};
    Marpa::R2::exception( "lexeme rule not allowed in G0\n",
        "  Rule was ", $parse->positions_to_string( $start, $end ) )
        if $op_declare ne q{::=};
    my $adverb_list = $unevaluated_adverb_list->evaluate();

    # A default rule clears the previous default
    $parse->{default_lexeme_adverbs} = {};

    ADVERB: for my $key ( keys %{$adverb_list} ) {
        my $value = $adverb_list->{$key};
        if ( $key eq 'action' ) {
            $parse->{default_lexeme_adverbs}->{$key} = $value;
            next ADVERB;
        }
        if ( $key eq 'bless' ) {
            $parse->{default_lexeme_adverbs}->{$key} = $value;
            next ADVERB;
        }
        Marpa::R2::exception(qq{"$key" adverb not allowed in default rule"});
    } ## end ADVERB: for my $key ( keys %{$adverb_list} )
    return undef;
} ## end sub evaluate

package Marpa::R2::Internal::MetaG_Nodes::priority_rule;
sub evaluate {
    my ( $values, $parse ) = @_;
    my ( $start, $end, $lhs, $op_declare, $priorities ) =
        @{$values};
    return $values->g0_evaluate($parse) if $op_declare->name() ne q{::=};
    return
        bless [
        map { Marpa::R2::Internal::MetaAST::dwim_evaluate( $_, $parse ) }
            @{$values} ],
        __PACKAGE__;
} ## end sub evaluate

sub g0_evaluate {
    my ( $values, $parse ) = @_;
    $DB::single = 1;
    return;
}
