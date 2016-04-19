#This is a basic VCL configuration file for varnish.  See the vcl(7)
#man page for details on VCL syntax and semantics.
#
#Default backend definition.  Set this to point to your content
#server.
#

import std;

# instances graysquirrel

backend instance_1 {
  .host = "haproxy";
  .port = "5000";
  .probe = {
         .url = "/varnish_probe";
         .interval = 30s;
         .timeout = 3s;
         .window = 5;
         .threshold = 3;
    }
}

# this is for anonymous requests to staging eea site
director eea_director random {
    .retries = 5;
    { .backend = instance_1; .weight = 1; }
}

# this is for anonymous requests to staging eea site
director eea_download round-robin {
    { .backend = instance_1; }
}

# this is for authenticated requests to staging eea site
director eea_authenticated round-robin {
    { .backend = instance_1; }
}

# who is allowed to send purge requests
acl purge {
    "10.116.228.25";
    "10.116.228.26";
    "localhost";
    "127.0.0.1";
}

sub vcl_recv {

    set req.grace = 120s;

    # Before anything else we need to fix gzip compression
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } else if (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } else if (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm
            remove req.http.Accept-Encoding;
        }
    }
    if (req.http.X-Forwarded-Proto == "https" ) {
        set req.http.X-Forwarded-Port = "443";
    } else {
        set req.http.X-Forwarded-Port = "80";
        set req.http.X-Forwarded-Proto = "http";
    }

    # we serve eea.europa.eu
    if (req.url ~ "^/VirtualHostBase/http/(.*?)eea.europa.eu")
    {
        set req.http.host = "eea.europa.eu";

        # cache authenticated requests by adding header
        set req.http.X-Username = "Anonymous";
        if (req.http.Cookie && req.http.Cookie ~ "__ac(|_(name|password|persistent))=")
        {
            set req.http.X-Username = regsub( req.http.Cookie, "^.*?__ac=([^;]*);*.*$", "\1" );

            # pick up a round-robin instance for authenticated users
            set req.backend = eea_authenticated;

            # pass (no caching)
            unset req.http.If-Modified-Since;
            return(pass);
        }
        else
        {
            # login form always goes to the reserved instances
            if (req.url ~ "login_form$")
            {
                set req.backend = eea_authenticated;

                # pass (no caching)
                unset req.http.If-Modified-Since;
                return(pass);
            }
            else
            {
                # downloads go only to these backends
                if (req.url ~ "/(file|download)$" || req.url ~ "/(file|download)\?(.*)")
                {
                    set req.backend = eea_download;
                }
                else
                {
                    # pick up a random instance for anonymous users
                    set req.backend = eea_director;
                }
            }
        }
    }
    else
    {
        # pick up a random instance for anonymous users to the eea site
        set req.backend = eea_director;
    }


    # Handle special requests
    if (req.request != "GET" && req.request != "HEAD") {

        # POST - Logins and edits
        if (req.request == "POST") {
            return(pass);
        }

        # PURGE - The CacheFu product can invalidate updated URLs
        if (req.request == "PURGE") {
            if (!client.ip ~ purge) {
                error 405 "Not allowed.";
            }

            # replace normal purge with ban-lurker way - may not work
            # ban ("req.url == " + req.url);
            ban ("obj.http.x-url ~ " + req.url);
            error 200 "Ban added. URL will be purged by lurker";
        }

        return(pass);
    }

    ### always cache these items:

    # javascript
    if (req.request == "GET" && req.url ~ "\.(js)") {
        return(lookup);
    }

    ## images
    if (req.request == "GET" && req.url ~ "\.(gif|jpg|jpeg|bmp|png|tiff|tif|ico|img|tga|wmf)$") {
        return(lookup);
    }

    ## multimedia
    if (req.request == "GET" && req.url ~ "\.(svg|swf|ico|mp3|mp4|m4a|ogg|mov|avi|wmv)$") {
        return(lookup);
    }

    ## xml
    if (req.request == "GET" && req.url ~ "\.(xml)$") {
        return(lookup);
    }

    ## for some urls or request we can do a pass here (no caching)
    if (req.request == "GET" && (req.url ~ "aq_parent" || req.url ~ "manage$" || req.url ~ "manage_workspace$" || req.url ~ "manage_main$")) {
        return(pass);
    }

    ## lookup anything else
    return(lookup);
}

sub vcl_pipe {
    # This is not necessary if we do not do any request rewriting
    set req.http.connection = "close";
}

sub vcl_fetch {
    # needed for ban-lurker
    set beresp.http.x-url = req.url;

    # Varnish determined the object was not cacheable
    if (!(beresp.ttl > 0s)) {
        set beresp.http.X-Cacheable = "NO: Not Cacheable";
    }

    # SAINT mode
    # if we get error 500 jump to the next backend
    if (req.request == "GET" && req.backend != eea_authenticated && (beresp.status == 500 || beresp.status == 503 || beresp.status == 504)) {
        set beresp.saintmode = 10s;
        return (restart);
    }
    set beresp.grace = 30m;

    # cache all XML and RDF objects for 1 day
    if (beresp.http.Content-Type ~ "(text\/xml|application\/xml|application\/atom\+xml|application\/rss\+xml|application\/rdf\+xml)") {
        set beresp.ttl = 1d;
        set beresp.http.X-Varnish-Caching-Rule-Id = "xml-rdf-files";
        set beresp.http.X-Varnish-Header-Set-Id = "cache-in-proxy-24-hours";
    }

    # add Access-Control-Allow-Origin header for webfonts and truetype fonts
    if (beresp.http.Content-Type ~ "(application\/vnd.ms-fontobject|font\/truetype|application\/font-woff|application\/x-font-woff)") {
        set beresp.http.Access-Control-Allow-Origin = "*";
    }

    #intecept 5xx errors here. Better reliability than in Apache
    if ( beresp.status >= 500 && beresp.status <= 505) {
                error beresp.status beresp.response;
    }
}

sub vcl_deliver {
    # needed for ban-lurker, we remove it here
    unset resp.http.x-url;

    # add a note in the header regarding the backend
    set resp.http.X-Backend = req.backend;

    # add more cache control params for authenticated users so browser does NOT cache, also do not cache ourselves
    if (req.backend == eea_authenticated)
    {
      set resp.http.Cache-Control = "max-age=0, no-cache, no-store, private, must-revalidate, post-check=0, pre-check=0";
      set resp.http.Pragma = "no-cache";
    }

    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    unset resp.http.error50x;
}

sub vcl_error {
    if (obj.status == 503 && req.backend != eea_authenticated && req.request == "GET" && req.restarts < 2) {
        return (restart);
    }

    set obj.http.Content-Type = "text/html; charset=utf-8";

    if ( obj.status >= 500 && obj.status <= 505) {
        set obj.http.error50x = std.fileread("/var/static/500msg.html");
        synthetic obj.http.error50x;
    } else {
        synthetic {"
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html>
        <head>
        <title>"} + obj.status + " " + obj.response + {"</title>
        </head>
        <body>
        <h1>Error "} + obj.status + " " + obj.response + {"</h1>
        <p>"} + obj.response + {"</p>
        <h3>Guru Meditation:</h3>
        <p>XID: "} + req.xid + {"</p>
        <address>
        <a href="http://www.varnish-cache.org/">Varnish</a>
        </address>
        </body>
        </html>
        "};
    }

    return (deliver);
}


# Below is a commented-out copy of the default VCL logic.  If you
# redefine any of these subroutines, the built-in logic will be
# appended to your code.
# sub vcl_recv {
#     if (req.restarts == 0) {
#         if (req.http.x-forwarded-for) {
#             set req.http.X-Forwarded-For =
#                 req.http.X-Forwarded-For + ", " + client.ip;
#         } else {
#             set req.http.X-Forwarded-For = client.ip;
#         }
#     }
#     if (req.request != "GET" &&
#       req.request != "HEAD" &&
#       req.request != "PUT" &&
#       req.request != "POST" &&
#       req.request != "TRACE" &&
#       req.request != "OPTIONS" &&
#       req.request != "DELETE") {
#         /* Non-RFC2616 or CONNECT which is weird. */
#         return (pipe);
#     }
#     if (req.request != "GET" && req.request != "HEAD") {
#         /* We only deal with GET and HEAD by default */
#         return (pass);
#     }
#     if (req.http.Authorization || req.http.Cookie) {
#         /* Not cacheable by default */
#         return (pass);
#     }
#     return (lookup);
# }
#
# sub vcl_pipe {
#     # Note that only the first request to the backend will have
#     # X-Forwarded-For set.  If you use X-Forwarded-For and want to
#     # have it set for all requests, make sure to have:
#     # set bereq.http.connection = "close";
#     # here.  It is not set by default as it might break some broken web
#     # applications, like IIS with NTLM authentication.
#     return (pipe);
# }
#
# sub vcl_pass {
#     return (pass);
# }
#
# sub vcl_hash {
#     hash_data(req.url);
#     if (req.http.host) {
#         hash_data(req.http.host);
#     } else {
#         hash_data(server.ip);
#     }
#     return (hash);
# }
#
# sub vcl_hit {
#     return (deliver);
# }
#
# sub vcl_miss {
#     return (fetch);
# }
#
# sub vcl_fetch {
#     if (beresp.ttl <= 0s ||
#         beresp.http.Set-Cookie ||
#         beresp.http.Vary == "*") {
#                 /*
#                  * Mark as "Hit-For-Pass" for the next 2 minutes
#                  */
#                 set beresp.ttl = 120 s;
#                 return (hit_for_pass);
#     }
#     return (deliver);
# }
#
# sub vcl_deliver {
#     return (deliver);
# }
#
# sub vcl_error {
#     set obj.http.Content-Type = "text/html; charset=utf-8";
#     set obj.http.Retry-After = "5";
#     synthetic {"
# <?xml version="1.0" encoding="utf-8"?>
# <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
#  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
# <html>
#   <head>
#     <title>"} + obj.status + " " + obj.response + {"</title>
#   </head>
#   <body>
#     <h1>Error "} + obj.status + " " + obj.response + {"</h1>
#     <p>"} + obj.response + {"</p>
#     <h3>Guru Meditation:</h3>
#     <p>XID: "} + req.xid + {"</p>
#     <hr>
#     <p>Varnish cache server</p>
#   </body>
# </html>
# "};
#     return (deliver);
# }
#
# sub vcl_init {
#         return (ok);
# }
#
# sub vcl_fini {
#         return (ok);
# }
