ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    sqlite \
    mariadb-client \
    openssh-client \
    jq \
    curl \
    bash

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
