package WebAPI::DBIC::Resource::Base;

=head1 NAME

WebAPI::DBIC::Resource::Base - Base class for WebAPI::DBIC::Resource's

=head1 DESCRIPTION

This class is simply a pure subclass of WebAPI::DBIC::Resource.

=cut

use Moo;
extends 'Web::Machine::Resource';

with 'WebAPI::DBIC::Resource::Role::Route';

use Carp qw/confess/;
use String::CamelCase qw(camelize decamelize);

require WebAPI::HTTP::Throwable::Factory;

has writable => (
    is => 'ro',
    default => 0,
);

has pathpart => (
    is      => 'lazy',
    builder => 1,
);

sub _build_pathpart {
    my ($self) = @_;

    return $self->type_name_for_schema_source($self->resultset->result_source);
}

has http_auth_type => (
   is => 'ro',
);

has throwable => (
    is => 'rw',
    default => 'WebAPI::HTTP::Throwable::Factory',
);

# specify what information should be used to define the url path/type of a schema class
# (result_name is deprecated and only supported for backwards compatibility)
has type_name_from  => (is => 'ro', default => 'source_name'); # 'source_name', 'result_name'
# decamelize how type_name_from should be formatted
has type_name_style => (is => 'ro', default => 'decamelize'); # 'original', 'camelize', 'decamelize'

has resultset => (
    is      => 'ro',
    builder => 1,
);

sub _build_resultset {
    my ($self) = @_;

    return $self->schema->resultset(($self =~ /Resource::(.*)/));
}

sub type_name_for_schema_source {
    my ($self, $source_name) = @_;

    my $type_name;
    if ($self->type_name_from eq 'source_name') {
        $type_name = $source_name;
    }
    elsif ($self->type_name_from eq 'result_name') { # deprecated
        my $result_source = $self->schema->source($source_name);
        $type_name = $result_source->name; # eg table name
        $type_name = $$type_name if ref($type_name) eq 'SCALAR';
    }
    else {
        confess "Invaid type_name_from: ".$self->type_name_from;
    }

    if ($self->type_name_style eq 'decamelize') {
        $type_name = decamelize($type_name);
    }
    elsif ($self->type_name_style eq 'camelize') {
        $type_name = camelize($type_name);
    }
    else {
        confess "Invaid type_name_style: ".$self->type_name_from
            unless $self->type_name_style eq 'original';
    }

    return $type_name;
}


1;
