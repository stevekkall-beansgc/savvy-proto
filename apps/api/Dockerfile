FROM ruby:3.4-slim@sha256:65680693964528b522a38d85ec5065538c7ab9e75268802aab9770f39ee56de0
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev postgresql-client && rm -rf /var/lib/apt/lists/*
WORKDIR /work/apps/api
COPY apps/api/Gemfile* ./
ENV BUNDLE_FROZEN=true
RUN bundle install
ENV BUNDLE_GEMFILE=/work/apps/api/Gemfile
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3101"]
