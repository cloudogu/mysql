FROM registry.cloudogu.com/official/base-debian:11.2-2

LABEL MAINTAINER="hello@cloudogu.com" \
        NAME="testing/mysql" \
        VERSION="5.7.31-4"

ENV PATH="${PATH}:/opt/mysql/bin" \
    MYSQL_VERSION=5.7.31 \
    MYSQL_HOME=/opt/mysql \
    MYSQL_VOLUME=/opt/mysql/data \
    MYSQL_TEMPDIR=/opt/mysql/temp \
    MYSQL_ERR_MESSAGES_DIR=/opt/mysql/share \
    MYSQL_ERR_MESSAGES_FILE=/opt/mysql/share/errmsg.sys \
    MYSQL_MY_CONF_DIR=/etc/my.cnf.d \
    MYSQL_DOGU_CONF_DIR=/etc/my.cnf.dogu.d \
    USER=mysql \
    GROUP=mysql

RUN curl -L -o /mysql.tar.gz https://downloads.mysql.com/archives/get/p/23/file/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.gz

RUN apt-get update && \
    apt-get install -y libaio1 libaio-dev libnuma-dev libncurses5 && \
    mkdir -p "${MYSQL_HOME}" "${MYSQL_VOLUME}" "${MYSQL_TEMPDIR}" "${MYSQL_ERR_MESSAGES_DIR}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}" && \
    touch "${MYSQL_ERR_MESSAGES_FILE}" && \
    addgroup "${GROUP}" && \
    adduser --gecos "" --home "${MYSQL_VOLUME}" --ingroup "${GROUP}" --disabled-login "${USER}" && \
    tar -xvzf /mysql.tar.gz --strip-components 1 -C "${MYSQL_HOME}" && \
    chown -R "${USER}":"${GROUP}" "${MYSQL_HOME}" "${MYSQL_VOLUME}" "${MYSQL_TEMPDIR}" "${MYSQL_ERR_MESSAGES_DIR}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}" && \
    apt-get clean

COPY resources/ /

EXPOSE 3306

HEALTHCHECK CMD doguctl healthy mysql || exit 1

# Re-using user and group outweighs negative outcomes
# dockerfile_lint - ignore
USER "${USER}":"${GROUP}"

CMD ["/startup.sh"]
