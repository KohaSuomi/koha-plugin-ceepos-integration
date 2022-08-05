package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions;

use Modern::Perl;

use Exception::Class (

    'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::NotFound' => {
        description => 'Not found',
    },
    'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest' => {
        description => 'Bad request',
    }
);

1;