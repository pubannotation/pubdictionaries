FROM ruby:3.4.2

ENV BUILD_PACKAGES="ruby-dev bash less" \
    DEV_PACKAGES="libxml2-dev libxslt-dev tzdata swig" \
    RUBY_PACKAGES="ruby-json nodejs git"

# Update and install base packages and nokogiri gem that requires a
# native compilation
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y \
    $BUILD_PACKAGES \
    $DEV_PACKAGES \
    $RUBY_PACKAGES

# Install the simstring gem
RUN mkdir -p /simstring
WORKDIR /simstring
RUN git clone https://github.com/chokkan/simstring.git
WORKDIR /simstring/simstring
RUN autoreconf -i
RUN ./configure
RUN make
WORKDIR /simstring/simstring/swig/ruby/
RUN ./prepare.sh --swig
RUN ruby extconf.rb
RUN make
RUN make install

# Copy the app into the working directory. This assumes your Gemfile
# is in the root directory and includes your version of Rails that you
# want to run.
RUN mkdir -p /myapp
WORKDIR /myapp
COPY Gemfile /myapp
COPY Gemfile.lock /myapp

RUN bundle config build.nokogiri --use-system-libraries && \
    bundle install --jobs=4 --retry=10

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
RUN chmod +x /docker-entrypoint.sh
CMD ["bin/rails", "s", "-b", "0.0.0.0"]
