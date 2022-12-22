FROM ruby:3.1

# Ensure the locale is set to UTF-8 to avoid encoding errors on non-ASCII paths
RUN echo 'locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8' | debconf-set-selections && \
    echo 'locales locales/default_environment_locale select en_US.UTF-8' | debconf-set-selections
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -qy --no-install-recommends install locales

ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

COPY app/Gemfile app/Gemfile.lock /app/
WORKDIR /app
RUN bundle install

COPY app /app

# For the tests
RUN mkdir /tmp/test_backup_output

ENV PATH="/app/bin:${PATH}"
CMD /bin/bash
