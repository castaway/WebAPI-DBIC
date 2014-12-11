package WebAPI::DBIC::WebApp;

use Moo;

use Module::Runtime qw(use_module);
use Carp qw(croak confess);
use JSON::MaybeXS qw(JSON);
use IO::All;

use Devel::Dwarn;

use Web::Machine;

# pre-load some modules to improve shared memory footprint
require DBIx::Class::SQLMaker;

use namespace::clean;

has schema => (is => 'ro', required => 1);
has http_auth_type => (is => 'ro', default => 'Basic');
has router_class => (is => 'ro', builder => 1);
has app_name => (is => 'ro', required => 1);
has resource_classes => (
    is      => 'lazy',
    builder => 1,
);

sub _build_resource_classes {
    return [
        map {
            s/\//::/g;
            $_;
        } grep {s#t/lib/(.+).pm#$1#} io('t/lib/'.shift->app_name.'/WebAPI/Resource')->All # XXX
    ];
}


sub _build_router_class {
    use_module('WebAPI::DBIC::Router');
    return 'WebAPI::DBIC::Router';
}

sub mk_generic_dbic_item_set_routes {
    my ($self, $resource_class) = @_;

    my $resource = use_module($resource_class)->new;

    if ($ENV{WEBAPI_DBIC_DEBUG}) {
        warn sprintf "Auto routes for /%s => resultset %s, result_class %s\n",
            $resource->pathpart, $resource->resultset, $resource->resultset->result_class;
    }

    return $resource->routes;
}

sub all_routes {
    my ($self) = @_;

    my @routes = map {
        $self->mk_generic_dbic_item_set_routes($_)
    } @{ $self->resource_classes };

    return @routes;
}

sub to_psgi_app {
    my ($self) = @_;

    my $router = $self->router_class->new;

    my @routes = $self->all_routes;

    while (my $path = shift @routes) {
        my $spec = shift @routes or confess "panic";

        $self->add_webapi_dbic_route($router, $path, $spec);
    }

    $self->add_webapi_dbic_route($router, '', {
        resource_class => 'WebAPI::DBIC::Resource::GenericRoot',
        resource_args  => {},
        #route_defaults => $route_defaults,
    });

    return $router->to_psgi_app; # return Plack app
}

sub add_webapi_dbic_route {
    my ($self, $router, $path, $spec) = @_;

    if ($ENV{WEBAPI_DBIC_DEBUG}) {
        my $route_defaults = $spec->{route_defaults} || {};
        my @route_default_keys = grep { !/^_/ } keys %$route_defaults;
        (my $class = $spec->{resource_class}) =~ s/^WebAPI::DBIC::Resource//;
        warn sprintf "/%s => %s (%s)\n",
            $path, $class,
            join(' ', map { "$_=$route_defaults->{$_}" } @route_default_keys);
    }

    my $getargs = $spec->{getargs};
    my $resource_args  = $spec->{resource_args}  or confess "panic";
    my $resource_class = $spec->{resource_class} or confess "panic";
    use_module $resource_class;

    # this sub acts as the interface between the router and
    # the Web::Machine instance handling the resource for that url path
    my $target = sub {
        my $request = shift; # url args remain in @_

        #local $SIG{__DIE__} = \&Carp::confess;

        my %resource_args_from_params;
        # perform any required setup for this request & params in @_
        $getargs->($request, \%resource_args_from_params, @_) if $getargs;

        warn "$path: running machine for $resource_class (args: @{[ keys %resource_args_from_params ]})\n"
            if $ENV{WEBAPI_DBIC_DEBUG};

        my $app = Web::Machine->new(
            resource => $resource_class,
            resource_args => [ %$resource_args, %resource_args_from_params ],
            tracing => $ENV{WEBAPI_DBIC_DEBUG},
        )->to_app;

        my $resp = eval { $app->($request->env) };
        #Dwarn $resp;
        if ($@) { # XXX report and rethrow
            warn "EXCEPTION during request for $path: $@";
            die; ## no critic (ErrorHandling::RequireCarping)
        }

        return $resp;
    };

    $router->add_route(
        path        => $path,
        validations => $spec->{validations} || {},
        defaults    => $spec->{route_defaults},
        target      => $target,
    );

    return;
}

1;
__END__
