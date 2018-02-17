FROM ruby:2.3

RUN mkdir /work/

ADD Gemfile /work/

RUN cd /work/ && bundle install

ADD logflowtester.rb work

ENTRYPOINT ["ruby", "/work/logflowtester.rb"]
