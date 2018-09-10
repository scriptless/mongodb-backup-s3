FROM mongo

# Install Python and Cron
RUN apt-get update && apt-get -y install awscli cron

ENV CRON_TIME="0 3 * * *" \
  TZ=Asia/Singapore \
  CRON_TZ=Asia/Singapore

ADD run.sh /run.sh
CMD /run.sh
