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
