FROM mongo

# Install Python and Cron
RUN apt-get update && apt-get -y install awscli cron

ENV CRON_TIME="0 3 * * *" \
  TZ=Asia/Novosibirsk \
  CRON_TZ=Asia/Novosibirsk

ADD run.sh /run.sh
CMD /run.sh
