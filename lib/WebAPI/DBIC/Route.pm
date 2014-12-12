package WebAPI::DBIC::Route;

=head1 NAME

WebAPI::DBIC::Route - A URL path to a WebAPI::DBIC Resource

=head1 DESCRIPTION

=cut

use Moo;

use Module::Runtime qw(use_module);


has path => (
    is => 'ro',
    required => 1,
);

has resource_class => (
    is => 'ro',
    required => 1,
);

has resource_args => (
    is => 'ro',
    required => 1,
);

has route_defaults => (
    is => 'ro',
);

has validations => (
    is => 'ro',
    default => sub { {} },
);


sub as_add_route_args {
    my $self = shift;

    if ($ENV{WEBAPI_DBIC_DEBUG}) {
        my $route_defaults = $self->route_defaults || {};
        my @route_default_keys = grep { !/^_/ } keys %$route_defaults;
        (my $class = $self->resource_class) =~ s/^WebAPI::DBIC::Resource//;
        warn sprintf "/%s => %s (%s)\n",
            $self->path, $class,
            join(' ', map { "$_=$route_defaults->{$_}" } @route_default_keys);
    }

    use_module $self->resource_class; # move to BUILD?

    # introspect route to get path param :names
    my $prr = Path::Router::Route->new(path => $self->path);
    my $path_var_names = [
        map { $prr->get_component_name($_) }
        grep { $prr->is_component_variable($_) }
        @{ $prr->components }
    ];

    my $resource_args_from_route = sub {
        # XXX we should try to generate more efficient code here
        my $req = shift;
        my $args = shift;
        for (@$path_var_names) { #in path param name order
            if (m/^[0-9]+$/) { # an id field
                $args->{id}[$_-1] = shift @_;
            }
            else {
                $args->{$_} = shift @_;
            }
        }
    };

    # this sub acts as the interface between the router and
    # the Web::Machine instance handling the resource for that url path
    my $target = sub {
        my $request = shift; # url args remain in @_

        #local $SIG{__DIE__} = \&Carp::confess;

        my %resource_args_from_params;
        # perform any required setup for this request & params in @_
        $resource_args_from_route->($request, \%resource_args_from_params, @_);

        warn sprintf "%s: running machine for %s (args: @{[ keys %resource_args_from_params ]})\n",
                $self->path, $self->resource_class
            if $ENV{WEBAPI_DBIC_DEBUG};

        my $app = Web::Machine->new(
            resource => $self->resource_class,
            resource_args => [ %{$self->resource_args}, %resource_args_from_params ],
            tracing => $ENV{WEBAPI_DBIC_DEBUG},
        )->to_app;

        my $resp = eval { $app->($request->env) };
        #Dwarn $resp;
        if ($@) { # XXX report and rethrow
            warn sprintf "EXCEPTION during request for %s: %s", $self->path, $@;
            die; ## no critic (ErrorHandling::RequireCarping)
        }

        return $resp;
    };

    return (
        path        => $self->path,
        validations => $self->validations || {},
        defaults    => $self->route_defaults,
        target      => $target,
    );
}


1;
