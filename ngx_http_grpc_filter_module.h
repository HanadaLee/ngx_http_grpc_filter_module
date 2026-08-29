
/*
 * Copyright (C) Hanada
 */


#ifndef _NGX_HTTP_GRPC_FILTER_MODULE_H_INCLUDED_
#define _NGX_HTTP_GRPC_FILTER_MODULE_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if !defined(NGX_RESTY_EXT) || !(NGX_RESTY_EXT)
#error "ngx_http_grpc_filter_module requires NGX_RESTY_EXT"
#endif


typedef enum {
    NGX_HTTP_GRPC_ACCESS_FILTER = 0,
    NGX_HTTP_GRPC_REQUEST_FILTER,
    NGX_HTTP_GRPC_HEADER_FILTER,
    NGX_HTTP_GRPC_BODY_FILTER,
    NGX_HTTP_GRPC_FINALIZE_REQUEST_FILTER
} ngx_http_grpc_filter_phase_e;


typedef struct {
    ngx_array_t             phases[NGX_HTTP_GRPC_FINALIZE_REQUEST_FILTER + 1];
} ngx_http_grpc_filter_main_conf_t;


typedef struct {
    ngx_uint_t              phase;

    ngx_list_t             *headers;

    ngx_str_t              *method;
    ngx_str_t              *host;
    ngx_str_t              *uri;

    ngx_http_upstream_headers_in_t  *headers_in;

    ngx_chain_t           **body;

    ngx_int_t               rc;
} ngx_http_grpc_filter_ctx_t;


/*
 * Handlers follow nginx phase semantics: NGX_DECLINED advances to the next
 * handler in the same grpc phase, NGX_OK finishes the current grpc phase,
 * and other return values are propagated to the grpc hook caller. A grpc
 * phase with no handler or only declined handlers completes with NGX_OK.
 */
typedef ngx_int_t (*ngx_http_grpc_filter_pt)(ngx_http_request_t *r,
    ngx_http_grpc_filter_ctx_t *ctx);


ngx_int_t ngx_http_grpc_filter_get_method(ngx_http_request_t *r,
    ngx_http_grpc_filter_ctx_t *ctx, ngx_str_t **method);
ngx_int_t ngx_http_grpc_filter_set_method(ngx_http_request_t *r,
    ngx_http_grpc_filter_ctx_t *ctx, ngx_str_t *method);
ngx_int_t ngx_http_grpc_filter_get_host(ngx_http_request_t *r,
    ngx_http_grpc_filter_ctx_t *ctx, ngx_str_t **host);
ngx_int_t ngx_http_grpc_filter_get_uri(ngx_http_request_t *r,
    ngx_http_grpc_filter_ctx_t *ctx, ngx_str_t **uri);
ngx_int_t ngx_http_grpc_filter_set_uri(ngx_http_request_t *r,
    ngx_http_grpc_filter_ctx_t *ctx, ngx_str_t *uri);

ngx_int_t ngx_http_grpc_filter_access_hook(ngx_http_request_t *r);
ngx_int_t ngx_http_grpc_filter_request_hook(ngx_http_request_t *r,
    ngx_list_t *headers, ngx_str_t *method, ngx_str_t *host, ngx_str_t *uri);
ngx_int_t ngx_http_grpc_filter_header_hook(ngx_http_request_t *r);
ngx_int_t ngx_http_grpc_filter_body_hook(ngx_http_request_t *r,
    ngx_chain_t **body);
void ngx_http_grpc_filter_finalize_hook(ngx_http_request_t *r, ngx_int_t rc);

void ngx_http_grpc_filter_update_chain_last(ngx_chain_t **chain,
    ngx_chain_t ***last);


extern ngx_module_t  ngx_http_grpc_filter_module;


#endif /* _NGX_HTTP_GRPC_FILTER_MODULE_H_INCLUDED_ */
