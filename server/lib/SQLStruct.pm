#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
#
# This file is part of AURORA, a system to store and manage science data.
#
# AURORA is free software: you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free 
# Software Foundation, either version 3 of the License, or (at your option) 
# any later version.
#
# AURORA is distributed in the hope that it will be useful, but WITHOUT ANY 
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with 
# AURORA. If not, see <https://www.gnu.org/licenses/>. 
#
# Class: SQLStruct: class to convert a list structure into SQL logical operator statements.
#
package SQLStruct;

use strict;
use DBI;

sub new {
   my $class=shift;
   my $self={};
   bless ($self,$class);

   my %pars=@_;

   $self->{pars}=\%pars;

   # fetch structure to use for operations or create a new, empty one
   if ((!exists $pars{struct}) || ((ref($pars{struct}) ne "ARRAY") && (ref($pars{struct}) ne "HASH"))) { my @s; $self->{struct}=\@s; }
   else { $self->{struct}=$self->{pars}{struct}; delete $self->{pars}{struct}; }
   # make a selection of how to quote values
   if ((!exists $pars{dbi}) || (ref($pars{dbi}) !~ /^DBI\:\:.*$/)) { $self->{quotetype}="SIMPLE"; } 
   else { $self->{quotetype}="DBI"; }
   # tell the module to quote all values, no matter their content
   if ((!exists $pars{forcequote}) || ($pars{forcequote} != 1)) { $pars{forcequote}=0; }
   # allow prepending SQL statements to handle AND/OR logic
   if (!exists $pars{prepar}) { $pars{prepar}=""; } # prepend paranthesis of logical statement
   if (!exists $pars{prelog}) { $pars{prelog}=""; } # prepend the logical statement itself

   # other options are identname (iname) and ident valuename (ivname) to specify the table and fieldnames of the row and value
   # for queries where the keyname and its value resides in different tables. by default this mechanism is not used.
   $self->{usenames}=0;
   if ((exists $pars{iname}) || (exists $pars{ivname})) {
      # use ident- and value names in SQL expressions. Identname and value resides in different tables.
      $self->{usenames}=1;
      $self->{pars}{iname}=$self->{pars}{iname} || "INAME";
      $self->{pars}{ivname}=$self->{pars}{ivname} || "IVALUENAME";
   }

   # it also accepts iclean and vclean parameters to set sub's that clean the identifier and value

   # valid logical operators
   my %LOP=(
      "ALL"         => { unary=>1, },
      "AND"         => {},
      "ANY"         => { unary=>1, min=>1, },
      "BETWEEN"     => { unary=>1, min=>2, },
      "EXISTS"      => { unary=>1, min=>1, },
      "IN"          => { unary=>1, min=>1, max=>1, },
      "LIKE"        => {},
      "NOT"         => { unary=>1 },
      "OR"          => {},
      "SOME"        => { unary=>1, min=>1, },
   );

   # other operators
   my %OPER=(
      # comparison operators
      '>' => { max=>2 },  # gt
      '<' => { max=>2 },  # lt
      '=' => { max=>2 },  # eq
      '>=' => { max=>2 }, # ge
      '<=' => { max=>2 }, # le
      '<>' => { max=>2 }, # ne
      '!' => { max=>2, trans=>"IS NOT", noq=>1, allowed=>['NULL']},  # is not
      '-' => { max=>2, trans=>"IS", noq=>1, allowed=>['NULL'] },  # is
      # bitwise operators
      '&' => { max=>3 },
      '|' => { max=>3 },
      '^' => { max=>3 },
   );

   $self->{lop}=\%LOP;
   $self->{oper}=\%OPER;

   return $self;
}

# set/get 
sub struct {
   my $self = shift;
   my $s = shift;

   if (@_) {
      # this is a set
      if ((ref($s) eq "ARRAY") || (ref($s) eq "HASH")) {
         $self->{struct}=$s;
         return 1;
      } else {
         return 0;
      }
   } else {
      # this is a get
      return $self->{struct};
   }
}

sub convert {
   my $self = shift;
   my $struct = shift; # allow to set struct without using internal value

   sub simpleQuote {
      my $self=shift;
      my $s=shift;
      if (!defined $s) { $s=""; }
 
      return "\"$s\"";
   }

   sub dbiQuote {
      my $self=shift;
      my $s=shift;
      if (!defined $s) { $s=""; }
 
      my $dbi=$self->{pars}{dbi};
      return $dbi->quote($s);
   }

   sub simpleIdentifierQuote {
      my $self=shift;
      my $i=shift;
      if (!defined $i) { $i=""; }

      $i=~s/^[\"\']*(.*)$/$1/;
      $i=~s/^(.+)[\"\']*$/$1/;

      $i=~/^(([^\.]+)\.)?(.+)$/;
      my $table=$2 || "";
      $table=($table eq "" ? $table : "\"".$table."\".");
      my $col=$3 || "";
      $col=($col eq "" ? $col : "\"".$col."\"");
     
      return $table.$col;
   }

   sub dbiIdentifierQuote {
      my $self=shift;
      my $i=shift;
      if (!defined $i) { $i=""; }

      my $dbi=$self->{pars}{dbi};
      $i=~/^(([^\.]+)\.)?(.+)$/;
      my $table=$2;
      my $col=$3;
      return $dbi->quote_identifier(undef,undef,$table,$col);
   }

   sub simpleIdentifierClean {
      my $c=shift;

      # max length
      $c=substr($c,0,128);
      $c=~/^(([a-zA-Z\_]+)\.)?([a-zA-Z0-9\_\.\*]+).*$/;
      my $table=$1 || "";
      my $col=$3 || "";

      return $table.$col;
   }

   sub simpleValueClean {
      my $i=shift; # identifier name, so cleaning can take that into account
      my $r=shift; # row value to be cleaned

      if (!defined $r) { return $r; }

      # constrain length/size
      if ($r =~ /^\d+$/) {
         # its a number, do nothing
      } else {
         # limit to max 255 characters
         $r=substr($r,0,255);
      }

      return $r;
   }

   # HASH
   sub constraint {
      my $self=shift;
      my $ref=shift;
      my $field=shift || "";

      # nothing to do
      if (!defined $ref) { return ""; }

      # get potential field/value table and field info
      my $usenames=$self->{usenames};
      my $iname=$self->{pars}{iname} || "";
      my $vname=$self->{pars}{ivname} || "";

      # get quote settings
      my $quote=$self->{quote};
      my $quoteall=$self->{pars}{forcequote};
      my $quoteident=$self->{quoteident};

      # get clean settings
      my $iclean=$self->{pars}{iclean};
      my $vclean=$self->{pars}{vclean};

      # clean identifier name
      $field=$iclean->($field); 

      # get prepending setting
      my $prepar=($self->{pars}{prepar} eq "" ? "" : $self->{pars}{prepar}." ");
      my $prelog=($self->{pars}{prelog} eq "" ? "" : $self->{pars}{prelog}." ");

      # add a start paranthesis if more than one element in structure at this level
      my $par=((defined $ref) && (keys %{$ref} > 1) ? 1 : 0);
      my $sql=($par ? "(" : "");
      # find the logical operator based upon ref type
      my $op="AND";

      foreach (keys %{$ref}) {
         my $key=$_;

         if ((ref($ref->{$key}) eq "ARRAY") || (ref($ref->{$key}) eq "HASH")) {
            # this is an array or hash - recurse down into structure
            my $ret=recurse($self,$ref->{$key},$key);
            $sql=(($sql eq "(") || ($sql eq "") ? $sql.$ret : $sql." $op ".$ret);
         } else {
            # key is potentially an operator, if not a key
            my $pop=uc($key);
            my $oexists=exists $self->{oper}{$pop};
            # the value assignment of the key
            my $value=$ref->{$key};
            # clean identifier name if not operator
            $key=($oexists ? $key : $iclean->($key));
            # check field name for wildcarding if useunames
            my $fwildc=0;
            if ((!$oexists) && ($usenames)) {
               # escape percent-signs
               $key=~s/\%/\\\%/g;
               # allow wildcards
               $key=~s/(?<!\\)(\*)/\%/g;
               # remove escape on escaped *
               $key=~s/\\\*/\*/g;
               # check if wildcarding
               $fwildc=($key =~ /(?<!\\)\%/ ? 1 : 0);
            } elsif (($usenames) && ($oexists)) {
               # convert field instead
               $field=~s/\%/\\\%/g;
               # allow wildcards
               $field=~s/(?<!\\)(\*)/\%/g;
               # remove escape on escaped *
               $field=~s/\\\*/\*/g;
               # check if wildcarding
               $fwildc=($field =~ /(?<!\\)\%/ ? 1 : 0);
            }
            # quote field
            my $qfield=($oexists ? ($usenames ? $quote->($self,$field) : $quoteident->($self,$field)) : ($usenames ? $quote->($self,$key) : $quoteident->($self,$key)));
            # make an extra qfield and vname to be used for
            # comparator cases
            my $qfieldcmp=$qfield;
            my $vnamecmp=$vname;
            # clean value
            $value=($oexists ? $vclean->($qfield,$value) : $vclean->($key,$value));
            # escape percent-signs
            if (defined $value) { $value=~s/\%/\\\%/g; }
            # allow wildcards
            if (defined $value) { $value=~s/(?<!\\)(\*)/\%/g; }
            # remove escape on escaped *
            if (defined $value) { $value=~s/\\\*/\*/g; }
            # a value for usename and one without (used by numerical non-quoting logic)
            my $valuew=$value;
            my $valuewo=$value;
            # check if wildcarding
            my $wildc=0;;
            if (defined $value) { $wildc=($value =~ /(?<!\\)\%/ ? 1 : 0); }

            # overwrite comparator based upon if it exists as an operator or not
            # if operator, translate if necessary, if not just return comparator
            my $cmp=($oexists ? ($self->{oper}{$pop}{trans} || $key) : "=");
            # ensure we have wildcard replacement
            $cmp=($wildc ? ($cmp eq "=" ? "LIKE" : ($cmp eq "<>" ? "NOT LIKE" : $cmp)) : $cmp);

            # do not quote operators that are not to be quoted
            if ((!$oexists) || 
                (($oexists) && (!exists $self->{oper}{$pop}{noq}))) {
               # check if value is to be quoted
               if ($quoteall) {
                  # quote, remove potential start ' to avoid issues in output
                  $value=~s/^\'(.*)$/$1/;
                  $value=$quote->($self,$value);
                  $valuew=$value;
                  $valuewo=$value;
               } elsif ((defined $value) && ($value =~ /^\'(.*)$/)) {
                  # quote value
                  $value=$quote->($self,$1);
                  $valuew=$value;
                  $valuewo=$value;
               } elsif ((defined $value) && ($value !~ /^\-?\d+(\.\d+)?$/)) {
                  # quote value
                  $value=$quote->($self,$value);
                  $valuew=$value;
                  $valuewo=$value;
               } else {
                  # value is an integer value, we need to do some
                  # checks and adjustments
                  if ((defined $value) && ($value == 0)) {   
                     # value is a zero, special precautions
                     if ($cmp eq "=") {
                        #  FIELD $cmp "0" or FIELD $cmp "0.0"
                        $valuew="'0' OR $vname $cmp '0.0'";
                        $valuewo="'0' OR $qfield $cmp '0.0'"; 
                     } elsif ($cmp =~ /^[\<\>]{1}\=$/) { 
                        # FIELD = "0" or FIELD = "0.0" or FIELD+0 $cmp 0 
                        $valuew="0 OR $vname = '0' OR $vname = '0.0'";
                        $valuewo="0 OR $qfield = '0' OR $qfield = '0.0'";
                        $vnamecmp="$vname+0";
                        $qfieldcmp="$qfield+0";
                     } else {
                        # $vnamecmp="CAST($vname AS REAL)"; MySQL > 8.0.17
                        # qfieldcmp="CAST($qfield AS REAL)"; MySQL > 8.0.17
                        $vnamecmp="$vname+0";
                        $qfieldcmp="$qfield+0";
                     }
                  } elsif (defined $value) {
                     # value is non-zero, force casting of field to an INTEGER
                     # $vnamecmp="CAST($vname AS REAL)"; MySQL > 8.0.17
                     # qfieldcmp="CAST($qfield AS REAL)"; MySQL > 8.0.17
                     $vnamecmp="$vname+0";
                     $qfieldcmp="$qfield+0";
                  } else {
                     # value is undefined - set it to null
                     $vnamecmp="$vname";
                     $qfieldcmp="$qfield";
                     $value="NULL";
                     $valuew=$value;
                     $valuewo=$value;
                  }
               }
            }

            # ensure value does not violate possible constraints
            if (($oexists) && (exists $self->{oper}{$pop}{allowed})) {
              # ensure that value is one of the allowed ones
              my @list=@{$self->{oper}{$pop}{allowed}};
              my $all=0;
              foreach (@list) {
                 my $a=$_;
                 if (uc($value) eq $a) { $all=1; last;}
              }
              # if value is allowed, just use it, if not take first allowed element
              $value=($all ? $value : $list[0]);
            }

            # check if we are to add field and value tablenames
            if ($usenames) {
               # set field name comparator
               my $fcmp=($fwildc ? "LIKE" : "=");
               $sql=(($sql eq "(") || ($sql eq "") ? $sql."$prepar($prelog($iname $fcmp $qfield) AND ($vnamecmp $cmp $valuew))" : $sql." $op $prepar($prelog($iname $fcmp $qfield) AND ($vnamecmp $cmp $valuew))");
            } else {
               $sql=(($sql eq "(") || ($sql eq "") ? $sql."$prepar($prelog$qfieldcmp $cmp $valuewo)" : $sql." $op $prepar($prelog$qfieldcmp $cmp $valuewo)");
            }
         }
      }
      $sql=($par ? $sql.")" : $sql);
      return $sql;
   }
 
   # array
   sub conjunction {
      my $self=shift;
      my $ref=shift;

      if (!defined $ref) { return ""; }

      # get quote settings
      my $quote=$self->{quote};
      my $quoteall=$self->{pars}{forcequote};

      # get clean settings
      my $vclean=$self->{pars}{vclean};
	
      my $sql="";
      # add a start paranthesis if more than one element in structure at this level
      my $par=(@{$ref} > 2 ? 1 : 0);
      # find the logical operator based upon ref type
      my $lop=uc($ref->[0] || "OR");
      # remove prefix of potential operator. Operator is only last word.
      $lop=~s/^(.*\s+)?([^\s]+)$/$2/;
      my $op=(defined $ref->[0] ? uc($ref->[0]) : "OR");
      # separator between elements in list, initially the same as the LOP itself
      my $sep=$lop;     
      # only proceed if logical operators exists
      if (exists $self->{lop}{$lop}) {
         my $unary=$self->{lop}{$lop}{unary} || 0;
         # change separator if unary
         $sep=($unary ? "," : $sep);

         # if unary operator, ensure operator starts conjunction
         $sql=($par ? ($unary ? "$op (" : "(") : ($unary ? "$op ": ""));

         for (my $i=1; $i < @{$ref}; $i++) {
            my $el=$ref->[$i];

            # check if ref to array or hash
            if ((ref($el) eq "ARRAY") || (ref($el) eq "HASH")) {
               # this is an array or hash - recurse down into structure
               my $ret=recurse($self,$el);
               $sql=($i == 1 ? $sql.$ret : "$sql $sep $ret");
            } else {
               # scalar or something else, use as is
               my $value=$el;
               # clean it
               $value=$vclean->("",$value);
               if ($quoteall) {
                  # quote, remove potential start ' to avoid issues in output
                  $value=~s/^\'?(.*)/$1/;
                  $value=$quote->($self,$value);
               } elsif ($value =~ /^\'(.*)/) {
                  # quote value
                  $value=$quote->($self,$1);
               } elsif ($value !~ /^\-?\d+(\.\d+)?$/) {
                  # quote value
                  $value=$quote->($self,$value);
               } 

               $sql=($i == 1 ? "$sql $value" : "$sql $sep $value");
            }
         }
      }
      $sql=($par ? $sql.")" : $sql);
      return $sql;
   }

   # recurse through struct and create sql
   sub recurse {
      my $self=shift;
      my $ref=shift;
      my $field=shift;

      if (!defined $ref) { return ""; }

      if (ref($ref) eq "ARRAY") {
         return conjunction ($self,$ref);         
      } elsif (ref($ref) eq "HASH") {
         return constraint ($self,$ref,$field);
      }
   }

   # ensure an array, either by input or by fetching internal value
   $struct=((defined $struct) && ((ref($struct) eq "ARRAY") || (ref($struct) eq "HASH")) ? $struct : $self->struct() );

   # set quote settings
   my $dbi=$self->{pars}{dbi} || undef;
   $self->{quote}=($self->quoteType() eq "DBI" ? \&dbiQuote : \&simpleQuote);
   $self->{quoteident}=($self->quoteType() eq "DBI" ? \&dbiIdentifierQuote : \&simpleIdentifierQuote);

   # set clean settings
   $self->{pars}{iclean}=($self->{pars}{iclean} ? $self->{pars}{iclean} : \&simpleIdentifierClean);
   $self->{pars}{vclean}=($self->{pars}{vclean} ? $self->{pars}{vclean} : \&simpleValueClean);

   # recurse structure
   my $sql=recurse ($self,$struct);

   # return result
   return $sql || "";
}

sub quoteType {
   my $self = shift;

   return $self->{quotetype};
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<SQLStruct> - Create logical SQL statements from a structure of LISTS and HASHES.

=head1 SYNOPSIS

   use SQLStruct;

   my $sstruct=SQLStruct->new();

   my @s=( 'OR',
           { 'Creator' => 'Bård',
             'Created' => { '>' => '1990', '<' => '2000' }
           },
           { 'Creator' => 'Jan Frode*',
           },
           { 'Religion' => { '!' => "NULL", '-' => "NULL" }
           },
           '1',
           [ 'not',
              { 'Group' => 'Whatever',
              },
             '11'
           ],
         );

   my $sql=$sstruct->convert(\@s);

   print $sql;

=head1 DESCRIPTION

This module creates logical SQL statements from a structure containing LIST(s) and HASH(es). The created logical 
SQL-statements are meant to be used after the WHERE-clause in a SQL-query.

=head1 CONSTRUCTOR

=head2 new()

Required input is none. Optional parameters are:

=over 1

=item I<struct>

The structure to create SQL from. It should be either an ARRAY or a HASH. The structure can be set after instantiation by calling the struct()-method.

=cut

=item I<dbi>

Sets the DBI-instance used by the caller so that one can perform proper SQL quoting, both for identifiers and values. If no DBI-instance is specified it will use internal, unsafe and simplified quoting functions.

=cut

=item I<forcequote>

Toggles that all values are to be quoted no matter what type they might be or what flags have been set on them.

=cut

=item I<iname>

Sets the identifier table name in case the identifier resides in one table and the value in another (see ivname parameter). This should typically be in the format:

TABLE.FIELD

The conversion process will assume that the field names in the structure are to be checked against the value in TABLE.FIELD.

=cut

=item I<ivname>

Sets the identifier value name in the the identifier resides in on table and the value in another (see iname parameter). This should typially be in the format:

TABLE.FIELD

The conversion process will assume that the values specified in the structure are to be checked against the value in TABLE.FIELD.

=cut

=item I<iclean>

Sets the reference to the function that clean the identifier. This cleans the identifier specified in the structure, not the identifier specified in the parameter iname.

=cut

=item I<vclean>

Sets the reference to the function that clean the value of the identifier. This cleans the value of the identifier in the structure.

=cut

=item I<prepar>

Sets the prepended SQL before the paranthesis that contains the logical sub query statement. Can allow for checking of values that would normally come on multiple rows. Eg. prepar=>"id in" (see complimentary option example in prelog below).

=cut

=item I<prelog>

Sets the prepended SQL before the logical sub query statement. Can allow for checking of values that would normally come on multiple rows. Eg. prelog=>"SELECT id FROM T1 LEFT JOIN T2 on T1.id=T2.id LEFT JOIN T3 on T2.key=T3.key WHERE".

=cut

=back

Return instance upon success.

=cut

=head1 METHODS

=head2 struct()

Sets or gets the structure used by the class. 

The function takes one optional parameter when setting the structure.

When setting the structure the type must be a reference to a HASH or an ARRAY. When retrieving the structure returned will be a reference to a HASH or LIST.

=cut

=head2 convert()

The main function of the class that converts the structure into standard SQL.

Takes one optional parameter with the structure to be used for conversion instead of using the one set at instantiation or through the struct()-method.

The structure is either a LIST or HASH-reference. The structure must be in the form:

   ( "LOP",

      { FIELDx => { "COP" => "VALUE", "COP" => "VALUE", }, 

      { FIELDy => { "COP" => "VALUE" }, 

      { FIELDz => { "COP" => "VALUE" }, 

   ) 

Where the first element of every LIST/ARRAY is the LOP or logical operator for the rest of the elements in the LIST. Default operator is "OR" if an invalid one is specified. It always assumes that the first element is the logical operator and will skip this when handling the lists elements. If the logical operator in a LISt is a unary the elements in that list are comma-separated.

The COP is the comparison operator that are to be used. All hash key/value pairs in a specific hash are always AND'ed together.

Valid LOPs are: I<ALL>, I<AND>, I<ANY>, I<BETWEEN>, I<EXISTS>, I<IN>, I<LIKE>, I<NOT>, I<OR> and I<SOME>. Accepted prefix'es to unary LOPs are whatever you want to (usual SQL engines only accepts ones like NOT, +, - etc.). The convert function only looks at the last word after the last space to know which operator is requested. Please also note that not all these LOPs might be supported by the SQL-engine being used. 

Valid COPs are: > (greater than), < (lesser than), <> (not equal to), = (equal to), >= (greater than or equal), <= (lesser than or equal), ! (is not), - (not), & (bitwise and), | (bitwise or) and ^ (bitwise xor).

If the value of a comparison contains a wildcard "*" it is converted to "%" and if the comparator is "=" or "<>", the comparator is converted to "LIKE" or "NOT LIKE" accordingly. If "*" is to be used as the value itself it must be escaped.

When setting option iname and/or ivname (see new()-method) the conversion process also allows wildcards in the field name, since both the field-name and the value resides in columns in tables.

One can force quoting of a value by either prefix'ing the value with a B<'> or by setting the forcequote option in the constructor to 1.
If a value is neither prefixed to be quoted or forcequote is turned on, it will decide to quote or not based upon if the value
is a purely decimal value or not? If it is a purely decimal value it will not be quoted.

It should also be noted that if force quoting is disabled, the convert()-method will handle comparators with INTEGER-values in a special manner. 
INTEGER values are specified as consisting of "-", "." and numbers 0-9. In this scenario, if the search value for a field consists of an 
INTEGER, it will follow a logic that ensures typecasting in such a manner that even VARCHAR data fields will be able to understand that 
we are dealing with INTEGER comparisons and not STRING or VARCHAR. It is especially important to handle comparisons with zero correctly as 
how this is interpreted depends on the SQL engine in question and how it typecasts the field and value. It has been attempted to keep 
this logic working on the following SQL-engines: MySQL, SQLite, Oracle and PostgreSQL. We have not done extensive testing with SQLStruct on 
these engines, but we have checked and tested type cast logic on: >= MySQL 5.6, >= SQLite 3.22.0, >= Oracle 11g R2, >= PostgreSQL 9.6 (thanks 
to SQL Fiddle - sqlfiddle.com). When checking against zero values, this forced typecasting will understand "0" as well as "0.0" being the 
same value.

=cut

=head2 quoteType()

Returns the type of quoting used. Two types exists: SIMPLE and DBI. The SIMPLE type is the built-in, simple quoting functions, while DBI uses the DBI instance's quoting routines (quote()- and quote_identifier()-methods).

The return value is a SCALAR.

=cut

