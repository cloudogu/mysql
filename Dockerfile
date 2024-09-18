FROM registry.cloudogu.com/official/base-debian:12.6-1

LABEL MAINTAINER="hello@cloudogu.com" \
        NAME="official/mysql" \
        VERSION="8.0.38-3"

ENV PATH="${PATH}:/var/lib/mysql/bin" \
    MYSQL_VOLUME=/var/lib/mysql \
    MYSQL_MY_CONF_DIR=/etc/my.cnf.d \
    MYSQL_DOGU_CONF_DIR=/etc/my.cnf.dogu.d \
    STARTUP_DIR="" \
    DEV_DEPENDENCIES="wget gnupg lsb-release" \
    WORKDIR=""

COPY installation-scripts /

RUN set -eux \
 && apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y libaio1 libaio-dev libnuma-dev libncurses5 procps libc-bin ${DEV_DEPENDENCIES} \
 && /install-mysql.sh \
    # Make sure all directories exists and have correct permissions
 && mkdir -p "${MYSQL_VOLUME}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}" \
    # Remove pre generated configuration
 && rm -rf /etc/mysql \
    # Cleanup
 && apt-get purge -y ${DEV_DEPENDENCIES} \
 && apt-get -y autoremove \
 && apt-get -y clean

COPY resources /

EXPOSE 3306

HEALTHCHECK --interval=5s CMD doguctl healthy mysql || exit 1

CMD ["/startup.sh"]
