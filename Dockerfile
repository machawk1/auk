FROM       ruby:2.4

RUN apt-get update -qq && apt-get install -qq -y build-essential libpq-dev git gcc libxml2-dev build-essential

# GraphPass installation
RUN wget http://igraph.org/nightly/get/c/igraph-0.7.1.tar.gz; tar -xvzf igraph-0.7.1.tar.gz
RUN cd igraph-0.7.1; ./configure; make -s; make install; ldconfig

# Get a more updated node than provided by apt directly
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt-get install -y nodejs

RUN mkdir /auk
WORKDIR /auk

COPY Gemfile /auk/Gemfile
COPY Gemfile.lock /auk/Gemfile.lock
COPY ./config/application.yml.example /auk/config/application.yml

RUN bundle install

COPY . /auk
RUN /auk/bin/rails db:migrate RAILS_ENV=development

CMD rails s