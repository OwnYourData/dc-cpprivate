FROM oydeu/dc-base
MAINTAINER "Christoph Fabianek" christoph@ownyourdata.eu

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		nodejs \
		cron \
		libyaml-dev \
		ca-certificates \
		gnupg \
		build-essential \
		libv8-dev \
		libnode-dev \
		python3 \
		curl && \
	mkdir -p /etc/apt/keyrings && \
	curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
		gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
	NODE_MAJOR=18 && \
	apt-get update && \
	apt-get install nodejs -y && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY Gemfile.extend $WORKDIR
RUN git config --global url."https://".insteadOf git:// && \
	gem update --system && \
	bundle update --bundler && \
	bundle install && \
	bundle update

COPY . .
RUN bundle install

CMD ["./script/init.sh"]
EXPOSE 3000
