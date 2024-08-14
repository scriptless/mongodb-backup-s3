FROM mongo:7

ENV CRON_TIME="0 3 * * *" \
  TZ=Europe/Berlin \
  CRON_TZ=Europe/Berlin

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
