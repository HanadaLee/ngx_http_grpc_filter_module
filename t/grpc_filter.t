#!/usr/bin/perl

# End-to-end tests for the grpc filter hook framework.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http grpc rewrite
	ngx_http_grpc_filter_module/)
	->plan(14);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8081;
        server_name  backend;

        http2 on;
        default_type application/grpc;
        add_trailer grpc-status 0 always;

        location = /body {
            return 200 lower-body;
        }

        location = /body-large {
            alias %%TESTDIR%%/large;
        }

        location / {
            return 200 "$request_method|$request_uri|$http_x_grpc_filter_host|$http_x_grpc_filter_original_uri|$http_x_grpc_filter_first|$http_x_grpc_filter_second";
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /basic {
            grpc_filter_test on;
            grpc_set_header Host custom.example;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /default-host {
            grpc_filter_test on;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /rewrite {
            grpc_filter_test on;
            grpc_filter_test_uri /changed?z=1;
            grpc_filter_test_method POST;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /stop {
            grpc_filter_test on;
            grpc_filter_test_stop on;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /access {
            grpc_filter_test on;
            grpc_filter_test_access_status 418;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /header {
            grpc_filter_test on;
            grpc_filter_test_response_header on;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /content-type {
            grpc_filter_test on;
            grpc_filter_test_response_content_type on;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /body {
            grpc_filter_test on;
            grpc_filter_test_body_uppercase on;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /body-large {
            grpc_filter_test on;
            grpc_filter_test_body_uppercase on;
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /disabled {
            grpc_pass grpc://127.0.0.1:8081;
        }

        location = /finalize {
            grpc_filter_test on;
            grpc_filter_test_finalize on;
            grpc_pass grpc://127.0.0.1:8081;
        }
    }
}

EOF

$t->write_file('large', 'lower-body-' x 4096);
$t->run()->waitforsocket('127.0.0.1:' . port(8080));

###############################################################################

is(body('/basic'), 'GET|/basic|custom.example|/basic|1|1',
	'request phase exposes Host and URI and runs handlers in reverse order');
like(body('/default-host'),
	qr/^GET\|\/default-host\|127\.0\.0\.1:8081\|\/default-host\|1\|1$/,
	'get_host falls back to the grpc upstream host');
is(body('/rewrite'), 'POST|/changed?z=1|127.0.0.1:8081|/rewrite|1|1',
	'request phase can replace method and URI');
is(body('/stop'), 'GET|/stop|127.0.0.1:8081|/stop||1',
	'NGX_OK stops earlier handlers in the same phase');

like(response('/access'), qr/^HTTP\/1\.1 418 /,
	'access phase status aborts grpcing');
like(response('/header'), qr/^X-Grpc-Filter-Response: set\x0d?$/mi,
	'header phase adds an upstream response header');
like(response('/content-type'),
	qr{^Content-Type: application/grpc\+filtered\x0d?$}mi,
	'response header handlers use the value modified by the header phase');

is(body('/body'), 'LOWER-BODY',
	'body phase transforms decoded grpc response chunks');

my $large = body('/body-large');
is(length($large), 11 * 4096,
	'body phase preserves a response spanning multiple chunks');
unlike($large, qr/[a-z]/,
	'body phase transforms every chunk in a large response');
is(substr($large, 0, 22), 'LOWER-BODY-LOWER-BODY-',
	'large response content remains in order');

is(body('/disabled'), 'GET|/disabled||||',
	'disabled test consumer leaves grpcing unchanged');

is(body('/finalize'), 'GET|/finalize|127.0.0.1:8081|/finalize|1|1',
	'finalized request still returns its upstream response');

my $log = $t->read_file('error.log');
my @finalized = $log =~ /grpc filter test finalized: \/finalize /g;
is(scalar @finalized, 1, 'finalize phase runs once per request');

###############################################################################

sub body {
	return http_content(response(@_));
}


sub response {
	my ($uri) = @_;

	return http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: close

EOF
}

###############################################################################
