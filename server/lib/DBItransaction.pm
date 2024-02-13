#!/usr/bin/perl -w
# Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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
use strict;

package DBItransaction;

our $DBItransaction; # Cross instance 

sub new {
    my $class = shift;
    my $DBI = shift or return;

    my $self = bless({}, ref($class) || $class);

    $self->{DBI} = $DBI;
    $self->{rollbackonerror} = 1;

    $self->{previousAutoCommit} = $DBI->{AutoCommit};
    $DBI->begin_work() if $self->{previousAutoCommit};

    $DBItransaction = {} if $self->mine or not defined $DBItransaction; # No outer transaction
    $self->{DBItransaction} = $DBItransaction;

    return $self;
}

sub mine {
    my $self = shift;
    return 0 if $self->{inhibit};
    return(!$self->{DBI}->{AutoCommit} and $self->{previousAutoCommit});
}

sub inhibit {
    my $self = shift;
    $self->{inhibit} = 1;
}

sub commit {
    my $self = shift;
    if ($self->mine()) {
	if (my $reason = $self->rollingback()) {
	    $self->setcommiterr("Rollback in progress: $reason");
	    return 0;
	}
	my $DBI = $self->{DBI};
	my $rc = $DBI->commit();
	$self->setcommiterr(DBI->errstr) unless $rc;
	return $rc;
    }
    else {
	return 1;
    }
}
sub setcommiterr {
    my $self = shift;
    if (@_) { $self->{DBItransaction}{commiterr} = shift; }
    else    { delete($self->{DBItransaction}{commiterr}); };
}
sub commiterr {
    my $self = shift;
    return $self->{DBItransaction}{commiterr};
}

sub rollbackonerror {
    my $self = shift;
    if (@_) {
        $self->{rollbackonerror} = shift || 0;
        return $self;
    }
    else {
        return $self->{rollbackonerror};
    }
}   

sub rollback {
    my $self = shift;
    my $reason = shift || $self->rollingback || "Rolling back";
    if ($self->mine()) {
	my $DBI = $self->{DBI};
	my $rc = $DBI->rollback();
	$self->setrollbackerr("$reason: ".$DBI->errstr) unless $rc;
	return $rc;
    }
    else {
	$self->setrollingback($reason);
	return 1;
    }
}
sub setrollingback {
    my $self = shift;
    return $self->{DBItransaction}{rollingback} = shift;
}
sub rollingback {
    my $self = shift;
    return $self->{DBItransaction}{rollingback};
}
sub cancelrollback {
    my $self = shift;
    delete($self->{DBItransaction}{rollingback});
    $self->setrollbackerr();
    return 1;
}
sub setrollbackerr {
    my $self = shift;
    if (@_) { $self->{DBItransaction}{rollbackerr} = shift; }
    else    { delete($self->{DBItransaction}{rollbackerr}); };
}
sub rollbackerr {
    my $self = shift;
    return $self->{DBItransaction}{rollbackerr};
}

sub end {
    my $self = shift;
    my $DBI = $self->{DBI};
    if ( $DBI->err 
         and $self->rollbackonerror
         and !$self->rollingback
        ) {
        $self->setrollingback($DBI->errstr||"Unknown error!");
    }
    #
    if ($self->rollingback) {
        $self->rollback();
    }
    else {
        $self->commit() || $self->rollback($self->comitterr);
    }
}

sub clear {
    my $self;
    $self->setcommiterr();
    $self->cancelrollback();
    $self->inhibit(); 
}

sub DESTROY {
    my $self = shift;
    $self->end();
}

# Optional - DBItransaction inherits other DBI methods.
sub AUTOLOAD {
    our $AUTOLOAD;
    my $self = shift;
    (my $method = $AUTOLOAD) =~ s/^.*://;
    return $self->{DBI}->$method(@_);
}

1;

__END__

=encoding UTF-8

=head1 NAME

C<DBItransaction> - Class to handle transactions on a DBI-instance.

=cut

=head1 SYNOPSIS

   use DBItransaction;

   # DBI instance
   my $dbi=DBI->new(SOME_INIT....);

   # create instance
   my $t=DBItransaction->new($dbi);

   # create instance with error values set in a class instances data
   my $t=DBItransaction->new($dbi,$instance);

=cut

=head1 DESCRIPTION

Class to handle transactions on a DBI-instance. If nested, the outmost instance will own the transaction. mine() will reflect ownership to the transaction. 

On end() (called implicitely from DESTROY) a rollback() will be run if commit() fails.

commit() fails if
    $DBItransaction::DBItransaction{rollingback} is true
    or DBI->err is true and rollbackonerror() is true
    or mine() and DBI->commit fails

rollback() do a DBI->rollback if mine(), otherwise it signals a rollback by setting $DBItransaction::DBItransaction{rollingback} to true;

A signalled rollback can be cancelled by cancelrollback() if the problem is resolved. 


=cut

=head1 CONSTRUCTOR

=head2 new()

Instantiates the DBItransaction class.

It takes one parameter:

=over

=item

B<DBI> The DBI-instance that one is performing transactions on. Required.

=cut

=back 

Returns the DBItransaction instance upon success.

=cut

=head1 METHODS

=head2 mine()

Returns if the commit belongs to this DBItransaction instance or not.

The return can be moderated by the inhibit()-method. See the inhibit()-method for more information.

=cut

=head2 inhibit()

Inhibits committing changes even if this instance of DBItransaction owns the commit/started the transaction.

No accepted input to this method.

No return from this method.

=cut

=head2 commit()

Commits the transactional record.

This is only done if this instance of DBItransaction owns the commit/started the transaction (see the mine()-method).

It also not done if a rollback is already in progress for some reason.

Returns 1 upon success, 0 upon failure. 

Please check the commiterr()-method for more information upon failure. Or in the case of 
automatic DBItransaction-DESTROY upon end of a function or block and the err-option was set on instantiation, the error will be 
found in the err-instance (see the new()-method).

=cut

=head2 setcommiterr()

Set the commit error. 

Input is the error-string as a SCALAR.

No return from method.

This is an internal method and is not to be called by user.

=cut

=head2 commiterr()

Gets the commit error.

No input accepted.

The return is the commit error SCALAR (if any).

=cut

=head2 rollback()

Attempts to run a rollback of the transactional record of the DBI-instance.

Optional input is the reason for the rollback.

It will only attempt a rollback if the DBItransaction-instance in question own the commit/start of the transaction 
(see the mine()-method).
If the transaction is not "mine" a rollback request is signalled by detting the package global $DBItransaction{rollingback} to true (reason || 1);

It returns 1 upon success, 0 upon failure.

Please check the rollbackerr()-method for more information upon failure.

=cut

=head2 rollbackonerror()

Sets/get rollbackonerror policy.
If rollbackonerror is set on this DBItransaction object, a rollback is attempted/signalled on $trancsaction->end (or DESTROY). 

=item

b<boolean> Optional parameter to set rollbackonerror status. 

=cut

If no parameter is supplied, it return the rollbackonerror status. If new status is supplied it return $self. 

=cut

=head2 rollbackonerror()

Optional input is a boolen. If defined, sets the rollbackonerror option to the indicated value. On end() (or DESTROY()) rollback(DBI->errstr) is called if DBI->err;

Returns the rollbackonerror flag if given without parameter. With parameter it returns $self.

=cut

=head2 rollingback()

Returns the rollingback flag of the err-option.

See the new()-method for more information on the err-option.

=cut

=head2 cancelrollback()

Removes the rollingback flag of the err-option.

See the new()-method for more information on the err-option.

=cut

=head2 setrollbackerr()

Sets the rollback error.

Input is the rollback error as a SCALAR.

It has no return.

See the rollbackerr()-method for information on getting the rollback-error. This is an internal method and should not be called 
by the user.

=cut

=head2 rollbackerr()

Gets the rollback error message.

It has no accepted input.

Returns the rollback error message as a SCALAR.

See the err-option of the new()-method for more information on the location of error-messages.

=cut

=head2 end()

If mine()
Attempts to commit transaction or rollback if any error.

No input is accepted.

Returns the output from method commit() or rollback(). A commit or a rollback will only be performed if this instance owns 
the commit/start of the transaction and it has not been inhibited (see the mine()- and inhibit()-methods).

=cut

=head2 clear()

Clears the instance commit error, cancels any rollback and enables inhibiting of commits.

No input accepted and no return value.

=cut

=head2 DESTROY()

Handles de de-instantiation of the DBItransaction instance.

It de-instantiates the DBItransaction-instance by calling the end()-method. See the end()-method for more information. 

It will basically automatically handle commits and rollback for you, even when the DBItransaction instance is being destroyed by 
a function- exit or end of a block.

=cut

=head2 AUTOLOAD()

AUTOLOAD-handler.

Makes it possible to call any DBI-method on the DBItransaction instance and thereby using it as a class that has inherited 
from the DBI-class.

See Autoloading in perlsub in the Perl documentation for more information on the AUTOLOAD mechanism.

=cut
