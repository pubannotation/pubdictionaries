---
layout: docs
title: Batch Annotation
permalink: /batch-annotation/
---

# Batch Annotation (Asyncronous annotation)

When you want to annotate a large amount of texts,
if you use the normal annotation API,
there is a chance of timeout of connection before you get the results.

In the case, you can use the API for batch annotation, which implements an asynchronous communication model.

For a batch annotation, the path _/annotation_request_ can be called using the _POST_ method,
with a _JSON array of objects_ which contain texts, as the body of the request.

Below is a simple example of JSON array of objects each of which include a block of text:

	[
		{
			"text": "I have a stomach ache."
		},
		{
			"text": "I have a sore throat."
		}
	]

If the above JSON array of object is stored in the file, _example.json_, a [cURL][cURL] command can be used as follows to send a batch annotation request to PubAnnotation:

<textarea class="bash" readonly="true" style="height:5em">
curl -H "content-type:application/json" -i -d @example.json "http://pubdictionaries.org/annotation_request?dictionaries=UBERON-AE"
</textarea>

(In this document, examples are shown using the [cURL][cURL] command. It is highly recommended to read the manual of the curl command to understand the examples properly.)

Note that the option, _-i_, tells the _curl_ command to show the HTTP header in the response.
The follow is a typical response of PubAnnotation:

	HTTP/1.1 303 See Other
	Date: Thu, 06 Apr 2017 09:27:38 GMT
	Server: nginx/1.10.2
	Content-Type: text/html; charset=utf-8
	Retry-After: 1.0043
	Location: http://pubdictionaries.org/annotation_result/annotation-result-ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed
	X-UA-Compatible: IE=Edge,chrome=1
	Cache-Control: no-cache
	(Unnecessary part truncated.)

A normal response will come with the status code 303 (See Other),
with the following two headers:
* Location : specifies the location where the client can access to retrieve the result of annotation
* Retry-After : specifies the duration (seconds) after which the client is recommented to access the location

To retrieve the result of annotation, you can access the location, after the time recommended through the header, _Retry-After_.

<textarea class="bash" readonly="true" style="height:5em">
curl "http://pubdictionaries.org/annotation_result/annotation-result-ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed"
</textarea>

Then, you will get the annotation results in JSON:

	[
		{
			"text" : "I have a stomach ache.",
			"denotations" : [
				{
					"span" : {
						"end" : 16,
						"begin" : 9
					},
					"obj" : "http://purl.obolibrary.org/obo/UBERON_0000945"
				}
			]
		},
		{
			"text" : "I have a sore throat.",
			"denotations" : [
				{
					"span" : {
						"end" : 20,
						"begin" : 14
					},
					"obj" : "http://purl.obolibrary.org/obo/UBERON_0000341"
				}
			]
		}
	]

Note that what PubDictionaries will do to the input JSON array of objects is to add the denotation object to each of the JSON object in the array: to read the _text_ object and to add the _denotation_ object. Consequently, in the resulting JSON array of objects,
* the order of the objects will be retained, and
* all the contents in each of the JSON object will be retained.

For example, if the input JSON objects include some other fields

	[
		{
			"text-ID": "1",
			"text": "I have a stomach ache."
		},
		{
			"text-ID": "2",
			"text": "I have a sore throat."
		}
	]

They will be retained in the output JSON

	[
		{
			"text-ID": "1",
			"text" : "I have a stomach ache.",
			"denotations" : [
				{
					"span" : {
						"end" : 16,
						"begin" : 9
					},
					"obj" : "http://purl.obolibrary.org/obo/UBERON_0000945"
				}
			]
		},
		{
			"text-ID": "2",
			"text" : "I have a sore throat.",
			"denotations" : [
				{
					"span" : {
						"end" : 20,
						"begin" : 14
					},
					"obj" : "http://purl.obolibrary.org/obo/UBERON_0000341"
				}
			]
		}
	]

Note that if an object in the input JSON array of objects already include a _denotation_ object, it will be replaced with a new one by PubDictionaries. In other words, the _denotation_ objects in the input JSON array of objects will be the only objects which will not be retained in the resulting JSON array of objects.


[cURL]: https://curl.haxx.se/
