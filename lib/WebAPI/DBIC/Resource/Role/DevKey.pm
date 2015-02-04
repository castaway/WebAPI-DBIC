package WebAPI::DBIC::Resource::Role::DevKey;

=head1 NAME

WebAPI::DBIC::Resource::Role::DevKey - API protection via developer keys and user identification in every request

=cut

use JSON;
use Moo::Role;

requires 'request';
requires 'set';

=head1 DESCRIPTION

Goal of this role is to ensure that users of the API (developers) only
access data belonging to the currently logged-in user.

To accomplish this we will need to:

1. Issue developer keys

2. Provide a "login user" endpoint which returns UI/HTML to log user in (?)

3. forbid any attempts to request user data without a valid user token

The user access restriction assumes that the DBIC Schema class has
loaded Schema::RestrictWithObject.

=cut

=head2 forbidden

Verify that the request contains all the developer + user data required to access the API. 

=cut

sub forbidden {
    my ($self) = @_;

    print STDERR "Checking if URI is forbidden ", $self->request->path, "\n";
    return 0 if($self->request->path =~ /login/);

    my $params = $self->request->parameters;
    if($self->request->content_type && $self->request->content_type =~ /json/) {
        $params = decode_json($self->request->content);
    }
    return 1 if(!$params->{'user_token'});

    my $user_token = $params->{'user_token'};
    ## Can we look up the user here or does this turn it bit topsy
    ## turvy? I guess we're not restricting user lookups in the schema .. are we?
    my $user = $self->set->result_source->schema->resultset('User')->find({ user_token => $user_token });
    return 1 if(!$user);

    $self->set->result_source->schema->can('restrict_with_object') &&
        $self->set->result_source->schema->restrict_with_object( $user );
    return 0;
}

1;
