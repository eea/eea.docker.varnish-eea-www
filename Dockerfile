FROM eeacms/varnish:3
MAINTAINER "European Environment Agency (EEA): IDM2 A-Team" <eea-edw-a-team-alerts@googlegroups.com>

RUN mkdir -p /var/static \
 && curl -o /etc/varnish/conf.d/staging.vcl -SL https://svn.eionet.europa.eu/repositories/Zope/trunk/www.eea.europa.eu/trunk/etc/varnish/default-staging.vcl \
 && curl -o /var/static/500msg.html -SL https://svn.eionet.europa.eu/repositories/Zope/trunk/www.eea.europa.eu/trunk/static/500msg.html
