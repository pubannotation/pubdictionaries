FROM ruby:3.0.1

ENV BUILD_PACKAGES="ruby-dev bash less" \
    DEV_PACKAGES="libxml2-dev libxslt-dev tzdata" \
    RUBY_PACKAGES="ruby-json nodejs git"

# Update and install base packages and nokogiri gem that requires a
# native compilation
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y \
    $BUILD_PACKAGES \
    $DEV_PACKAGES \
    $RUBY_PACKAGES && \
    mkdir -p /myapp

# Copy the app into the working directory. This assumes your Gemfile
# is in the root directory and includes your version of Rails that you
# want to run.
WORKDIR /myapp
COPY Gemfile /myapp
COPY Gemfile.lock /myapp

RUN bundle config build.nokogiri --use-system-libraries && \
    bundle install --jobs=4 --retry=10

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
RUN chmod +x /docker-entrypoint.sh
CMD ["bin/rails", "s", "-b", "0.0.0.0"]
