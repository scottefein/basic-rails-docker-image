FROM ubuntu:quantal
MAINTAINER scottfeinberg "feinberg.scott@gmail.com"
RUN mkdir /tmp/build
ADD ./stack/ /tmp/build
RUN LC_ALL=C DEBIAN_FRONTEND=noninteractive cd /tmp/build && ./cedar.sh
RUN rm -rf /tmp/build


#install git

RUN add-apt-repository -y ppa:git-core/ppa;\
  apt-get update;\
  apt-get -y install git

#install ruby
RUN mkdir /tmp/ruby;\
	apt-get install libreadline-dev;\
  cd /tmp/ruby;\
  curl http://cache.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz | tar xz;\
  cd ruby-2.0.0-p247;\
  chmod +x configure;\
  ./configure --disable-install-rdoc;\
  make;\
  make install;\
  gem install bundler --no-ri --no-rdoc

RUN mkdir /app;\
	git clone https://github.com/feinbergscott/test-rails-app.git /app

RUN cd /app;\
        bundle config --global --jobs 4;\
	bundle install --without development:test:cucumber:vagrant --path vendor/bundle --binstubs vendor/bundle/bin --deployment 

ENV LANG en_US.UTF-8
ENV LOG_LEVEL DEBUG
ENV RACK_ENV production
ENV RAILS_ENV production
