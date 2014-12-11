package WebAPI::DBIC::Resource::Role::Route;

use Moo::Role;
use namespace::clean;

use Carp qw/confess/;

has routes => (
    is      => 'lazy',
    builder => 1,
);

sub _build_routes {
    my ($self) = @_;

    my @routes;

    push @routes, $self->_build_set_routes;
    push @routes, $self->_build_item_routes;

    return @routes;
}

sub _build_set_routes {
    my ($self) = @_;

    my $rs              = $self->resultset;
    my $route_defaults  = $self->route_defauts;
    my $mk_getargs      = $self->_mk_getargs($rs);
    my $path            = $self->pathpart;

    my $invocable_on_set  = $self->invocable_on_set;
    $invocable_on_set  = [] unless $self->writable;

    my $qr_names = sub {
        my $names_r = join "|", map { quotemeta $_ } @_ or confess "panic";
        return qr/^(?:$names_r)$/x;
    };

    my @routes;
    push @routes, "$path" => { # set (aka collection)
        resource_class => $self,
        route_defaults => $route_defaults,
        getargs        => $mk_getargs->(),
    };

    push @routes, "$path/invoke/:method" => { # method call on set
        validations => { method => $qr_names->(@$invocable_on_set) },
        resource_class => $self,
        route_defaults => $route_defaults,
        getargs        => $mk_getargs->('method'),
    } if @$invocable_on_set;

    return @routes;
}

sub _build_item_routes {
    my ($self) = @_;

    my $rs = $self->resultset;
    my $route_defaults = $self->route_defaults;
    my $getargs = $self->_mk_getargs($rs);
    my $path = $self->pathpart;

    # XXX might want to distinguish writable from non-writable (read-only) methods
    my $invocable_on_item = $self->invocable_on_item;
    # disable all methods if not writable, for safety: (perhaps allow get_* methods)
    $invocable_on_item = [] unless $self->writable;

    my $qr_names = sub {
        my $names_r = join "|", map { quotemeta $_ } @_ or confess "panic";
        return qr/^(?:$names_r)$/x;
    };


    my $id_unique_constraint_name = $self->id_unique_constraint_name;
    my $uc = { $rs->result_source->unique_constraints }->{ $id_unique_constraint_name };

    my @routes;
    if ($uc) {
        my @key_fields = @$uc;
        my @idn_fields = 1 .. @key_fields;
        my $item_path_spec = join "/", map { ":$_" } @idn_fields;

        push @routes, "$path/$item_path_spec" => { # item
            #validations => { },
            resource_class => $self,
            route_defaults => $route_defaults,
            getargs        => $getargs->(@idn_fields),
        };

        push @routes, "$path/$item_path_spec/invoke/:method" => { # method call on item
            validations => {
                method => $qr_names->(@$invocable_on_item),
            },
            resource_class => $self,
            route_defaults => $route_defaults,
            getargs        => $getargs->(@idn_fields, 'method'),
        } if @$invocable_on_item;
    } else {
        warn sprintf "/%s/:id route skipped because %s has no $id_unique_constraint_name constraint defined\n",
            $path, $rs->result_class;
    }

    return @routes;
}

sub route_defaults {
    my ($self) = @_;

    return {
        # --- fields for route lookup
        result_class => $self->resultset->result_class,
        # --- fields for other uses
        # derive title from result class: WebAPI::Corp::Result::Foo => "Corp Foo"
        _title => join(" ", (split /::/, $self->resultset->result_class)[-3,-1]),
    };
}

sub _mk_getargs {
    my ($self) = @_;

    return sub {
        my @params = @_;
        # XXX we should try to generate more efficient code here
        return sub {
            my $req = shift;
            my $args = shift;
            $args->{set} = $self->resultset;
            for (@params) { #in path param name order
                if (m/^[0-9]+$/) { # an id field
                    $args->{id}[$_-1] = shift @_;
                }
                else {
                    $args->{$_} = shift @_;
                }
            }
        }
    };
}

1;
