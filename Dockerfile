FROM ruby:2.5.1

COPY app/Gemfile /app/Gemfile
WORKDIR /app
RUN bundle install

COPY app /app

