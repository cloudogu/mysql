FROM mysql:5.7.31

LABEL MAINTAINER="hello@cloudogu.com" \
        NAME="testing/mysql" \
        VERSION="5.7.31-2"

ENV USER=mysql \
    GROUP=mysql \
    MYSQL_ALLOW_EMPTY_PASSWORD="true"

COPY resources/ /

#RUN chown -R "${USER}:${GROUP}" /var/lib/mysql && chmod 777 /var/lib/mysql

EXPOSE 3306

HEALTHCHECK CMD doguctl healthy mysql || exit 1

#USER "${USER}":"${GROUP}"

#CMD ["mysqld"]
