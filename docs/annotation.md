---
layout: docs
title: Annotation
permalink: /annotation/
---

# Annotation

Once a dictionary is created on PubDictionaries, the dictionary can be used to annotate any text, through the [annotation API](/annotation-api/).

To annotate a piece of text, based on a dictionary,
the path _/text_annotation can be called either in the _GET_ or _POST_ method.
When it is call in the _GET_ method,
the piece of text can be sent through the parameter, _text_:

<textarea class="bash" readonly="true" style="height:5em">
curl -G --data-urlencode text="I have a stomach ache." http://pubdictionaries.org/text_annotation.json?dictionaries=UBERON-AE
</textarea>

(In this document, examples are shown using the [cURL][cURL] command. It is highly recommended to read the manual of the curl command to understand the examples properly.)

Then, the result of annotation will be returned in JSON, following the [PubAnnotation Annotation Format](http://www.pubannotation.org/docs/annotation-format/)

	{
		"text" : "I have a stomach ache.",
		"denotations" : [
			{
				"obj" : "http://purl.obolibrary.org/obo/UBERON_0000945",
				"span" : {
					"end" : 16,
					"begin" : 9
				}
			}
		]
	}

The path also can be called in the _POST_ method, in which case the text can be sent in JSON

<textarea class="bash" readonly="true" style="height:5em">
curl -H "content-type:application/json" -d '{"text":"I have a stomach ache."}' http://pubdictionaries.org/text_annotation.json?dictionaries=UBERON-AE
</textarea>

[cURL]: https://curl.haxx.se/
