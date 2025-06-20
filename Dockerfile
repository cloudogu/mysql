FROM registry.cloudogu.com/official/base-debian:12.9-1

LABEL MAINTAINER="hello@cloudogu.com" \
        NAME="official/mysql" \
        VERSION="8.4.6-0"

ENV PATH="${PATH}:/var/lib/mysql/bin" \
    MYSQL_VERSION="8.4.6" \
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
    && apt-get install -y libaio1 libaio-dev libnuma-dev libncurses5 procps libc-bin ${DEV_DEPENDENCIES}

# Install MySQL separately so it fails immediately if version not available
RUN /install-mysql.sh "${MYSQL_VERSION}"

RUN set -eux \
    # Make sure all directories exists and have correct permissions
    && mkdir -p "${MYSQL_VOLUME}" "${MYSQL_MY_CONF_DIR}" "${MYSQL_DOGU_CONF_DIR}" \
    # Remove pre generated configuration
    && rm -rf /etc/mysql \
    # Cleanup
    && apt-get purge -y ${DEV_DEPENDENCIES} \
    && apt-get -y autoremove \
    && apt-get -y clean \
    # Remove dev packages if not needed
    && apt-get purge -y libopenexr-dev || true \
    \
    # Force-remove risky libs and their rdeps (ImageMagick/HEIF)
    && apt-get purge -y --allow-remove-essential --allow-change-held-packages \
        libaom3 libavif15 libheif1 libopenexr-3-1-30 libmagickcore-6.q16-6-extra imagemagick || true \
    \
    && apt-get autoremove -y || true \
    && rm -rf /var/lib/apt/lists/* /tmp/* /root/*

COPY resources /

EXPOSE 3306

HEALTHCHECK --interval=5s CMD doguctl healthy mysql || exit 1

CMD ["/startup.sh"]
