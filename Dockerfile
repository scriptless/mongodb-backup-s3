FROM mongo:4.1

ENV CRON_TIME="0 3 * * *" \
  TZ=Australia/Adelaide \
  CRON_TZ=Australia/Adelaide

# Install Python and Cron
RUN \
  apt-get update && \
  apt-get --assume-yes --no-install-recommends install \
    awscli \
    cron && \
  rm -rf \
   /var/lib/apt/lists/* \
   /tmp/* \
   /var/tmp/*

ADD run.sh /run.sh
CMD /run.sh
