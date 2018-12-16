# PubDictionaries

## About
PubDictionaries aims to provide a platform in which users can easily share their dictionaries and automatically annotate texts with those dictionaries.

## Requirements
* Ruby v2.3.x
* Rails v3.2.x
* ElasticSearch v6.5.3
  * [ICU Analysis Plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/6.5/analysis-icu.html)

## Install
1. clone
1. bundle
1. rake db:create
1. rake db:migrate
1. echo "Entry.\__elasticsearch__.create_index!  force:true" | rails console

## Launch
rails s