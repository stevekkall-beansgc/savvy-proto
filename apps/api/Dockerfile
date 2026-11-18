FROM ruby:3.4-slim@sha256:65680693964528b522a38d85ec5065538c7ab9e75268802aab9770f39ee56de0
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev postgresql-client && rm -rf /var/lib/apt/lists/*
WORKDIR /work/apps/api
COPY apps/api/Gemfile* ./
ENV BUNDLE_FROZEN=true
RUN bundle install
COPY apps/api/app ./app
COPY apps/api/config/*.rb apps/api/config/database.yml ./config/
COPY apps/api/config/environments/development.rb ./config/environments/development.rb
COPY apps/api/config/initializers/filter_parameter_logging.rb ./config/initializers/filter_parameter_logging.rb
COPY apps/api/bin ./bin
COPY apps/api/config.ru apps/api/Rakefile ./
COPY fixtures/finance /work/fixtures/finance
COPY fixtures/synthetic /work/fixtures/synthetic
COPY fixtures/disclosures /work/fixtures/disclosures
COPY fixtures/medallion /work/fixtures/medallion
RUN ln -s /tmp /work/apps/api/tmp
ARG SOURCE_REVISION=unknown
LABEL org.opencontainers.image.revision=$SOURCE_REVISION
ENV SAVVY_SOURCE_REVISION=$SOURCE_REVISION
ENV BUNDLE_GEMFILE=/work/apps/api/Gemfile
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3101"]
