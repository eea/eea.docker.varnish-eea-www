FROM eeacms/varnish:4.1-2.0
MAINTAINER "European Environment Agency (EEA): IDM2 A-Team" <eea-edw-a-team-alerts@googlegroups.com>

COPY 500msg.html /etc/varnish/
COPY varnish.vcl /etc/varnish/conf.d/
