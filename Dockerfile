FROM alpine:3

# Variables set with ARG can be overridden at image build time with
# "--build-arg var=value".  They are not available in the running container.
ARG restic_ver=0.16.0
ARG tfc_ops_ver=3.5.4
ARG tfc_ops_distrib=tfc-ops_Linux_x86_64.tar.gz
ARG SENTRY_CLI_VERSION=2.41.1

# Install Restic, tfc-ops, perl, jq, and sentry-cli
RUN cd /tmp \
 && wget -O /tmp/restic.bz2 \
    https://github.com/restic/restic/releases/download/v${restic_ver}/restic_${restic_ver}_linux_amd64.bz2 \
 && bunzip2 /tmp/restic.bz2 \
 && chmod +x /tmp/restic \
 && mv /tmp/restic /usr/local/bin/restic \
 && wget https://github.com/sil-org/tfc-ops/releases/download/v${tfc_ops_ver}/${tfc_ops_distrib} \
 && tar zxf ${tfc_ops_distrib} \
 && rm LICENSE README.md ${tfc_ops_distrib} \
 && mv tfc-ops /usr/local/bin \
 && apk update \
 && apk add --no-cache \
    perl \
    perl-file-slurp \
    perl-file-temp \
    jq \
    curl \
 && curl -sL https://sentry.io/get-cli/ | SENTRY_CLI_VERSION="${SENTRY_CLI_VERSION}" sh \
 && rm -rf /var/cache/apk/*

COPY ./tfc-backup-b2.sh  /usr/local/bin/tfc-backup-b2.sh
COPY ./tfc-dump.pl       /usr/local/bin/tfc-dump.pl
COPY application/        /data/

WORKDIR /data

CMD [ "/usr/local/bin/tfc-backup-b2.sh" ]
