=head1 NAME

webapi-dbic-any.psgi - instant WebAPI::DBIC browser for any DBIx::Class schema

=head1 SYNOPSIS

    $ export WEBAPI_DBIC_SCHEMA=Foo::Bar     # your own schema
    $ export WEBAPI_DBIC_HTTP_AUTH_TYPE=none # recommended
    $ export DBI_DSN=dbi:Driver:...          # your own database
    $ export DBI_USER=... # for initial connection, if needed
    $ export DBI_PASS=... # for initial connection, if needed
    $ plackup webapi-dbic-any.psgi
    ... open a web browser on port 5000 to browse your new API

The API provided by this .psgi file will be read-only unless the
C<WEBAPI_DBIC_WRITABLE> env var is true.

For details on the C<WEBAPI_DBIC_HTTP_AUTH_TYPE> env var and security issues
see C<http_auth_type> in L<WebAPI::DBIC::Resource::Role::DBICAuth>.

=cut

use strict;
use warnings;

use Plack::Builder;
use Plack::App::File;
use WebAPI::DBIC::WebApp;
use Alien::Web::HalBrowser;

use MagicPantry::Model;

my $hal_app = Plack::App::File->new(
  root => Alien::Web::HalBrowser->dir
)->to_app;

my $schema_class = $ENV{WEBAPI_DBIC_SCHEMA}
    or die "WEBAPI_DBIC_SCHEMA env var not set";
eval "require $schema_class" or die "Error loading $schema_class: $@";

my $schema = $schema_class->connect(); # uses DBI_DSN, DBI_USER, DBI_PASS env vars

my $app = WebAPI::DBIC::WebApp->new({
    schema   => $schema,
    extra_routes => magic_pantry_routes(),
    route_maker => WebAPI::DBIC::RouteMaker->new(
        resource_class_for_item        => 'WebAPI::DBIC::Resource::GenericItem',
        resource_class_for_item_invoke => 'WebAPI::DBIC::Resource::GenericItemInvoke',
        resource_class_for_set         => 'WebAPI::DBIC::Resource::GenericSet',
        resource_class_for_set_invoke  => 'WebAPI::DBIC::Resource::GenericSetInvoke',
        resource_default_args          => { },
        resource_extra_roles           => [ 'WebAPI::DBIC::Resource::Role::DevKey' ],
   ),
})->to_psgi_app;

my $app_prefix = "/webapi-dbic";

builder {
    enable "SimpleLogger";  # show on STDERR

    mount "$app_prefix/" => builder {
        mount "/browser" => $hal_app;
        mount "/" => $app;
    };

    # root redirect for discovery - redirect to API
    mount "/" => sub { [ 302, [ Location => "$app_prefix/" ], [ ] ] };
};


## Extra non-dbic-source routes for magic pantry
## returns arrayref of arrayrefs, each with $path => (%args)
## args are validations (regex of matching urls), defaults (params) and target (coderef)
## NB:: WebApp will add its "schema" to the defaults
## See WebAPI::DBIC::Route as_add_route_args for where I stole the target creation from
sub magic_pantry_routes {
    return [
        [ 'login/?:connection_token' => (
            target => sub { 
                my $request = shift; # URL args from router remain in @_
                Web::Machine->new(
                    resource => 'MagicPantry::Resource::Login',
                    resource_args => [ connection_token => shift ],
                    tracing => $ENV{WEBAPI_DBIC_DEBUG},
                )->to_app->($request->env);
            },
           )
       ]
   ];
}
