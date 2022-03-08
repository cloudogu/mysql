FROM registry.cloudogu.com/official/base-debian:11.2-2

LABEL MAINTAINER="hello@cloudogu.com" \
        NAME="testing/mysql" \
        VERSION="5.7.31-4"

ENV PATH="${PATH}:/var/lib/mysql/bin" \
    MYSQL_VERSION=5.7.31 \
    MYSQL_VOLUME=/var/lib/mysql \
    MYSQL_MY_CONF_DIR=/etc/my.cnf.d \
    MYSQL_DOGU_CONF_DIR=/etc/my.cnf.dogu.d \
    STARTUP_DIR="" \
    DEV_DEPENDENCIES="sudo nano wget gnupg lsb-release" \
    USER=mysql \
    GROUP=mysql

COPY installation-scripts /

RUN apt-get update && \
    apt-get install -y libaio1 libaio-dev libnuma-dev libncurses5 procps libc-bin ${DEV_DEPENDENCIES} && \
    /install-mysql.sh && \
    mkdir -p "${MYSQL_VOLUME}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}" && \
    chown -R "${USER}":"${GROUP}" "${MYSQL_VOLUME}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}"
    apt purge -y ${DEV_DEPENDENCIES} && \
    apt -y autoremove && \
    apt -y clean

COPY resources /

EXPOSE 3306

HEALTHCHECK CMD doguctl healthy mysql || exit 1

# Re-using user and group outweighs negative outcomes
# dockerfile_lint - ignore
USER "${USER}":"${GROUP}"

CMD ["/startup.sh"]
