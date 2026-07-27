package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions;

use Modern::Perl;

use Exception::Class (

    'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::NotFound' => {
        description => 'Not found',
        fields      => ['code'],
    },
    'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest' => {
        description => 'Bad request',
        fields      => ['code'],
    }
);

1;