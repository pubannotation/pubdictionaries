# PubDictionaries

## About
PubDictionaries aims to provide a platform in which users can easily share their dictionaries and automatically annotate texts with those dictionaries.

## Requirements
* Ruby v2.3.x
* Rails v5.2.2
* ElasticSearch v6.5.3
  * [ICU Analysis Plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/6.5/analysis-icu.html)
  * [Korean (nori) Analysis plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/6.5/analysis-nori.html)

## Without docker

### Install
1. clone
1. bundle
1. rake db:create
1. rake db:migrate
1. echo "Entry.\__elasticsearch__.create_index!  force:true" | rails console

### Launch
rails s

## With docker

### Install
1. clone
1. docker-compose build

### Launch
1. docker-compose up

