# I: Runtime Stage: ============================================================
# This is the stage where we build the runtime base image, which is used as the
# common ancestor by the rest of the stages, and contains the minimal runtime
# dependencies required for the application to run:

# Step 1: Use the official Ruby 2.7.0 Slim Strech image as base:
FROM ruby:2.7.0-slim-buster AS runtime

# Step 2: We'll set the MALLOC_ARENA_MAX for optimization purposes & prevent memory bloat
# https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html
ENV MALLOC_ARENA_MAX="2"

# Step 3: We'll set the LANG encoding to be UTF-8 for special characters support
ENV LANG C.UTF-8

# Step 4: We'll set '/usr/src' path as the working directory:
# NOTE: This is a Linux "standard" practice - see:
# - http://www.pathname.com/fhs/2.2/
# - http://www.pathname.com/fhs/2.2/fhs-4.1.html
# - http://www.pathname.com/fhs/2.2/fhs-4.12.html
WORKDIR /usr/src

# Step 5: We'll set the working dir as HOME and add the app's binaries path to
# $PATH:
ENV HOME=/usr/src PATH=/usr/src/bin:$PATH

# Step 6: We'll install curl for later dependencies installations
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl

# Step 7: Add nodejs source
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash -

# Step 8: Add yarn packages repository
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

# Step 9: Install the common runtime dependencies:
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apt-transport-https software-properties-common \
    ca-certificates \
    libpq5 \
    openssl \
    nodejs \
    tzdata \
    yarn && \
    rm -rf /var/lib/apt/lists/*

# Step 10: Add Dockerize image
RUN export DOCKERIZE_VERSION=v0.6.1 && curl -L \
    https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    | tar -C /usr/local/bin -xz

# II: Development Stage: =======================================================
# In this stage we'll build the image used for development, including compilers,
# and development libraries. This is also a first step for building a releasable
# Docker image:

# Step 11: Start off from the "runtime" stage:
FROM runtime AS development

# Step 12: Set the default command:
CMD [ "rails", "server", "-b", "0.0.0.0" ]

# Step 13: Install the development dependency packages with alpine package
# manager:
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    chromium \
    chromium-driver \
    git \
    libpq-dev

# Step 14: Build the su-exec executable:
RUN curl -o /usr/local/bin/su-exec.c https://raw.githubusercontent.com/ncopa/su-exec/master/su-exec.c \
 && gcc -Wall /usr/local/bin/su-exec.c -o/usr/local/bin/su-exec \
 && chown root:root /usr/local/bin/su-exec \
 && chmod 0755 /usr/local/bin/su-exec \
 && rm /usr/local/bin/su-exec.c

# Step 15: Install the 'check-dependencies' node package:
RUN npm install -g check-dependencies

# Step 16: Copy the project's Gemfile + lock:
COPY Gemfile Gemfile.lock /usr/src/

# Step 17: Install the current project gems - they can be safely changed later
# during development via `bundle install` or `bundle update`:
RUN bundle install --jobs=4 --retry=3

# Step 18: Copy the project's npm dependency files:
COPY package.json yarn.lock /usr/src/

# Step 19: Install Yarn packages:
RUN yarn install

# Step 20: Receive the developer user's UID:
ARG DEVELOPER_UID=1000

# Step 21: Receive the developer user's username:
ARG DEVELOPER_USERNAME=you

# Step 22: Set the developer's UID as an environment variable:
ENV DEVELOPER_UID=${DEVELOPER_UID}

# Step 23: Create the developer user:
RUN useradd -r -M -u ${DEVELOPER_UID} -d /usr/src -c "Developer User,,," ${DEVELOPER_USERNAME}

# Stage III: Testing ===========================================================
# In this stage we'll add the current code from the project's source, so we can
# run tests with the code.

# Step 24: Start off from the development stage image:
FROM development AS testing

# Step 25: Copy the rest of the application code
COPY . /usr/src

# Step 26: Set the enrtypoint:
ENTRYPOINT [ "/usr/src/bin/dev-entrypoint.sh" ]

# Stage IV: Builder ============================================================
# In this stage we'll compile assets coming from the project's source, do some
# tests and cleanup:

# Step 27: Pick off from the testing stage image:
FROM testing AS builder

# Step 28: Precompile assets:
RUN export DATABASE_URL=postgres://postgres@example.com:5432/fakedb \
    SECRET_KEY_BASE=10167c7f7654ed02b3557b05b88ece \
    RAILS_ENV=production && \
    rails assets:precompile && \
    rails secret > /dev/null

# Step 29: Remove installed gems that belong to the development & test groups -
# the remaining gems will get copied to the releasable image in a later step:
RUN bundle config without development:test && bundle clean

# Step 30: Purge development/testing npm packages:
RUN yarn install --production

# Step 31: Remove files not used on release image:
RUN rm -rf \
    .rspec \
    Guardfile \
    bin/rspec \
    bin/checkdb \
    bin/dumpdb \
    bin/restoredb \
    bin/setup \
    bin/spring \
    bin/update \
    bin/dev-entrypoint.sh \
    config/spring.rb \
    spec \
    tmp/* \
  # Remove unneeded files (cached *.gem, *.o, *.c)
  && rm -rf /usr/local/bundle/cache/*.gem \
  && find /usr/local/bundle/gems/ -name "*.c" -delete \
  && find /usr/local/bundle/gems/ -name "*.o" -delete

# Stage V: Release =============================================================
# In this stage, we build the final, releasable Docker image, which should be
# smallest possible with the content generated on previous stages:

# Step 32: Start off from the runtime stage image:
FROM runtime AS release

# Step 33: Set the RAILS/RACK_ENV and PORT default values:
ENV RAILS_ENV=production RACK_ENV=production PORT=3000

# Step 34: Copy the "su-exec" executable:
COPY --from=builder /usr/local/bin/su-exec /usr/local/bin/su-exec

# Step 35: Copy the remaining installed gems from the "builder" stage:
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Step 36: Copy from app code from the "builder" stage, which at this point
# should have the assets from the asset pipeline already compiled:
COPY --from=builder --chown=nobody /usr/src /usr/src

# Step 37: Generate the temporary directories in case they don't already exist:
RUN mkdir -p /usr/src/tmp/cache /usr/src/tmp/pids /usr/src/tmp/sockets \
 && chown -R nobody:nobody /usr/src/tmp

# Step 38: Set the container user to 'nobody':
USER nobody

# Step 39: Check that there are no issues with rails' load paths, missing gems,
# etc:
RUN export DATABASE_URL=postgres://postgres@example.com:5432/fakedb \
    AWS_ACCESS_KEY_ID=SOME_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY=SOME_SECRET_ACCESS_KEY \
    SECRET_KEY_BASE=10167c7f7654ed02b3557b05b88ece && \
    rails runner "puts 'Looks Good!'"

# Step 40: Set the default command:
CMD [ "puma" ]

# Step 41 thru 45: Add label-schema.org labels to identify the build info:
ARG SOURCE_BRANCH="master"
ARG SOURCE_COMMIT="000000"
ARG BUILD_DATE="2017-09-26T16:13:26Z"
ARG IMAGE_NAME="icalialabs/rails-gci-saml-sso-demo:latest"

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="Rails with Google Cloud Identity SAML SSO Demo" \
      org.label-schema.description="ek-editores" \
      org.label-schema.vcs-url="https://github.com/IcaliaLabs/rails-gci-saml-sso-demo.git" \
      org.label-schema.vcs-ref=$SOURCE_COMMIT \
      org.label-schema.schema-version="1.0.0-rc1" \
      build-target="release" \
      build-branch=$SOURCE_BRANCH
