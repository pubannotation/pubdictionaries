# PubDictionaries

## About
PubDictionaries aims to provide a platform in which users can easily share their dictionaries and automatically annotate texts with those dictionaries.

## Requirements
* Ruby v3.4.x
* Rails v8.0.x
* SimString v1.0
  * [original version with documentation](http://www.chokkan.org/software/simstring/)
  * [modified version](https://github.com/pubannotation/simstring)
* ElasticSearch v7.x.x
  * [ICU Analysis Plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-icu.html)
  * [Japanese (Kuromoji) Analysis plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-kuromoji.html)
  * [Korean (nori) Analysis plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-nori.html)

## Without docker

### Install

Git clone and:

```shell
bundle
bin/rails db:create
bin/rails db:migrate
bin/rails runner script/create_index.rb
```

### Launch

```shell
bin/rails s
```

## With docker

### Install

```sh
docker compose build
```

### Launch

```sh
docker compose up
```

### Run tests

```sh
docker compose run --rm web bin/rails test
```

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

### ReCAPTCHA settings procedure

Access the Google reCAPTCHA site and log in with your Google account.
```
https://www.google.com/recaptcha/admin/create
```

The first screen that opens is the paid Enterprise version.  
Click "Switch to create a legacy key" to switch to the free version.
```
Switch to create a legacy key
```

Enter the required information.

label:
```
pubdictionaries
```

reCAPTCHA type:
```
v2 "I'm not a robot" checkbox
```

domain:  
Add your domain, example:
```
example.com
```

After you register your site, site_key and secret_key are generated.  
Add keys to .env file to use reCAPTCHA on your app.
```
RECAPTCHA_SITE_KEY=[Generated site key]
RECAPTCHA_SECRET_KEY=[Generated secret key]
```
