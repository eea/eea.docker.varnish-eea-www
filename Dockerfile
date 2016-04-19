FROM eeacms/varnish
MAINTAINER "European Environment Agency (EEA): IDM2 A-Team" <eea-edw-a-team-alerts@googlegroups.com>

USER root
COPY 500msg.html /etc/varnish/500msg.html
COPY varnish.vcl /etc/varnish/conf.d/varnish.vcl
USER varnish
