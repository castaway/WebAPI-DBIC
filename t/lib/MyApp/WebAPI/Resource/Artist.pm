package MyApp::WebAPI::Resource::Artist;

use Moo;

extends 'WebAPI::DBIC::Resource::GenericItem';
with 'WebAPI::DBIC::Resource::Role::ItemInvoke';

1;
