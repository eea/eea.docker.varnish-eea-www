FROM eeacms/varnish:debian
MAINTAINER "European Environment Agency (EEA): IDM2 A-Team" <eea-edw-a-team-alerts@googlegroups.com>

COPY 500msg.html default.vcl /etc/varnish/
COPY varnish.vcl /etc/varnish/conf.d/varnish.vcl
