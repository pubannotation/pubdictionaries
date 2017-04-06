---
layout: docs
title: Lookup
permalink: /lookup/
---

# Lookup

Once a dictionary is created on PubDictionaries, entries can be looked up though the [lookup API](/lookup-api/).

The _/find_ids_ path can be called in either _GET_ or _POST_ method.

When it is called in the _GET_ method, a list of labels (strings) can be sent through the _labels_ parameter.
Multiple labels may be delimited either by a newline('\n'), tab('\t'), or pipe ('|') character.

<textarea class="bash" readonly="true" style="height:5em">
curl -G -d labels="stomach|liver" http://pubdictionaries.org/find_ids.json?dictionaries=UBERON-AE
</textarea>

(In this document, examples are shown using the [cURL][cURL] command. It is highly recommended to read the manual of the curl command to understand the examples properly.)

Then, the result of lookup will be returned in a JSON hash:

	{
		"stomach" : [
			"http://purl.obolibrary.org/obo/UBERON_0000945"
		],
		"liver" : [
			"http://purl.obolibrary.org/obo/UBERON_0002107"
		]
	}

Note that a label may be mapped to multiple identifiers, which is why a label is mapped to an array of identifiers.

The path may be called in the _POST_ method, also, in which case, an array of lables can be sent in JSON through the body of the request.

	curl -H "content-type:application/json" -d '["stomach", "liver"]' "http://pubdictionaries.org/find_ids.json?dictionaries=UBERON-AE"

[cURL]: https://curl.haxx.se/