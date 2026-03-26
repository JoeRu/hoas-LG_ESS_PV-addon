FROM alpine:3.21

RUN apk add --no-cache \
    sqlite \
    mariadb-client \
    openssh-client \
    sshpass \
    jq \
    curl \
    bash

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
