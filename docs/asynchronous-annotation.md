---
layout: docs
title: Asynchronous Annotation
permalink: /asynchronous-annotation/
---

# Asynchronous Annotation

If you want to annotate a large amount of texts using a dictionary on PubDictionaries,
you can use the API for asynchronous annotation.

For an asynchronous annotation, the path _/annotation_request can be called in _POST_ method,
with an array of texts in JSON in the body of the POST request.

Suppose that a JSON file, _example.json_, has an array of JSON objects as follows:

	[
		{
			"text": "I have a stomach ache."
		},
		{
			"text": "I have a sore throat."
		}
	]

The content of the file can be sent to the above path as the body of the request

<textarea class="bash" readonly="true" style="height:5em">
curl -H "content-type:application/json" -i -d @example.json "http://pubdictionaries.org/text_annotation.json?dictionaries=UBERON-AE"
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

Note that a normal response will come with the status code 303 (See Other),
with particularly the following two headers:
* Location : specifies the location where the client can access to retrieve the result of annotation
* Retry-After : specifies the duration (seconds) after which the client is recommented to access the location

Following the instructions, you can access the location to retrieve the result of annotation

<textarea class="bash" readonly="true" style="height:5em">
curl "http://pubdictionaries.org/annotation_result/annotation-result-ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed"
</textarea>

Then, you will get the annotation in JSON:

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

Note that in the output JSON objects, all the content of the input JSON objects will be retained.

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

[cURL]: https://curl.haxx.se/
