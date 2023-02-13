FROM registry.cloudogu.com/official/base-debian:11.2-2

LABEL MAINTAINER="hello@cloudogu.com" \
        NAME="official/mysql" \
        VERSION="5.7.37-4"

ENV PATH="${PATH}:/var/lib/mysql/bin" \
    MYSQL_VOLUME=/var/lib/mysql \
    MYSQL_MY_CONF_DIR=/etc/my.cnf.d \
    MYSQL_DOGU_CONF_DIR=/etc/my.cnf.dogu.d \
    STARTUP_DIR="" \
    DEV_DEPENDENCIES="wget gnupg lsb-release" \
    WORKDIR=""

COPY installation-scripts /

RUN set -eux \
 && apt update \
 && apt upgrade -y \
 && apt-get install -y libaio1 libaio-dev libnuma-dev libncurses5 procps libc-bin ${DEV_DEPENDENCIES} \
 && /install-mysql.sh \
    # Make sure all directories exists and have correct permissions
 && mkdir -p "${MYSQL_VOLUME}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}" \
    # Remove pre generated configuration
 && rm -rf /etc/mysql \
    # Cleanup
 && apt purge -y ${DEV_DEPENDENCIES} \
 && apt -y autoremove \
 && apt -y clean

COPY resources /

EXPOSE 3306

HEALTHCHECK CMD doguctl healthy mysql || exit 1

CMD ["/startup.sh"]
