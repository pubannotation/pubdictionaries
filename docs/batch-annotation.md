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

A batch annotation request is initialized by POSTing an annotation task to the path _/annotation_tasks_ with a block of text as the body of the request:

Suppose that the text file, _example.txt_, has a piece of text, as below:

```text
I have a stomach ache.
```

Then, a [cURL][cURL] command can be used as follows to _POST_ an annotation task to PubAnnotation:
<textarea class="bash" readonly="true" style="height:5em">
curl -i -H "content-type:text/plain" -d @example.txt "http://pubdictionaries.org/annotation_tasks?dictionaries=UBERON-AE"
</textarea>

Note that in this document, examples are shown using the [cURL][cURL] command.
It is highly recommended to read the manual of the cURL command to understand the examples properly.

The command above sends the text in the file, _example.txt_, of which the MIME type is _text/plain_ to the path, _http://pubdictionaries.org/annotation_tasks?dictionaries=UBERON-AE_.
The option, _-i_, tells the _curl_ command to show the HTTP headers of the response.

Below is a typical response of PubDictionaries when the requested is successfully accepted (unnecessary headers are skipped):

```Bash
  HTTP/1.1 201 Created
  Content-Type: application/json; charset=utf-8
  Location: http://pubdictionaries.org/annotation_tasks/ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed

  {"submitted_at":"2020-03-29T11:26:37.542Z", "status":"in_queue", "ETR":3}
```
The response tells that the requested annotation task is successfully created at the location specified at the _Location_ header.

You can access the location to see the status of the task, e.g., using the follwing _curl_ command:
<textarea class="bash" readonly="true" style="height:3em">
curl -i http://pubdictionaries.org/annotation_tasks/ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed
</textarea>

Below is a typical response:

```Bash
  HTTP/1.1 200 OK 
  Content-Type: application/json; charset=utf-8

  {"submitted_at":"2020-03-29T11:26:37.542Z", "status":"in_progress", "ETR":1}
```
It tells you that the task is in the queue, and the estimated time of remaining is 2 second.
The status is one of _in_queue_, _in_progress_, or _done_.

While the response body is in JSON by default, you can receivd it in TSV (Tab-separated-values) by suffixing the location with '.csv' or '.tsv':
<textarea class="bash" readonly="true" style="height:3em">
curl -i http://pubdictionaries.org/annotation_tasks/ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed.csv
</textarea>


Below is a typical response when the status is _done_:
```Bash
  HTTP/1.1 200 OK 
  Content-Type: application/json; charset=utf-8

  submitted_at	2020-03-29 11:26:37 UTC
  status	done
  started_at	2020-03-29 11:27:26 UTC
  finished_at	2020-03-29 11:27:27 UTC
  result_location	http://pubdictionaries.org/annotation_results/annotation-ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed.json
```

It now shows the location _result_location_ which you can access, e.g., using the following _curl_ command:

<textarea class="bash" readonly="true" style="height:3em">
curl "http://pubdictionaries.org/annotation_results/annotation-ba8a0bb2-39b3-4530-a2a1-7da7c2df92ed.json"
</textarea>

Then, you will get the annotation results in JSON:

```JSON
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
```


If you want to send a multiple blocks of texts for an annotation task, you can put them in a JSON array as follows:

	[
		{
			"text": "I have a stomach ache."
		},
		{
			"text": "I have a sore throat."
		}
	]

When the above JSON array is stored in the file, _example.json_, the following [cURL][cURL] command sends it to PubDictionaries:

<textarea class="bash" readonly="true" style="height:5em">
curl -i -H "content-type:application/json" -d @example.json "http://pubdictionaries.org/annotation_request?dictionaries=UBERON-AE"
</textarea>

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
