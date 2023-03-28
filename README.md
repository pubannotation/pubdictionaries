# PubDictionaries

## About
PubDictionaries aims to provide a platform in which users can easily share their dictionaries and automatically annotate texts with those dictionaries.

## Requirements
* Ruby v3.2.x
* Rails v7.0.x
* SimString v1.0
  * [original version with documentation](http://www.chokkan.org/software/simstring/)
  * [modified version](https://github.com/pubannotation/simstring)
* ElasticSearch v7.x.x
  * [ICU Analysis Plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-icu.html)
  * [Japanese (Kuromoji) Analysis plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-kuromoji.html)
  * [Korean (nori) Analysis plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-nori.html)

## Without docker

### Install
1. clone
1. bundle
1. rake db:create
1. rake db:migrate
1. bin/rails runner script/create_index.rb

### Launch
rails s

## With docker

### Install
1. clone
1. docker-compose build

### Launch
1. docker-compose up

## Deployment

### Google authentication procedure

Execute the following ur in the browser and log in with the pubdictionaries specific user account.
```
https://console.developers.google.com/
```

Create a pubdictionaries project.
Example:
```
pubdictionaries
```

Click link(Enable APIs and services) to activate the API library:
```
Gmail API
```

OAuth consent screen.

User Type:
```
External
```
application name:
```
pubdictionaries
```

Create authentication information(OAuth Client ID).
Application type:
```
Web Application
```
After creating an OAuth client, client id and client secret are generated:

client id
```
99999999999-xx99x9xx9xxxxxx9x9xx9xx9xxxxxx.apps.googleusercontent.com
```
client secret
```
xxxxxxxxx9xxxx9xx9x9xx99
```

Add an approved redirect URI.
```
[Same URL as environment variable(pubdictionaries)]/users/auth/google_oauth2/callback
```

### Create .env file.
```
cp .env.example .env
```

### .env file settings.
```
CLIENT_ID=[Generated client id]
CLIENT_SECRET=[Generated client secret]
```
