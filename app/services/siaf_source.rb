# Build the input hash expected by SimpleInlineTextAnnotation.generate from a
# PubDictionaries annotator result (`{text:, denotations:}`). Populates an
# "entity types" config so the generator substitutes each URL with a
# short-label form AND emits a Markdown reference block resolving each label
# back to the URL — matching the extended SIAF spec.
#
# Shared by app/controllers/mcp_controller.rb (JSON tool result) and
# app/views/annotation/text_annotation.html.erb (in-browser SIAF preview).
module SiafSource
  extend self

  # Accepts denotations with either symbol or string keys (controller path
  # after JSON parse has strings; direct annotator output has symbols).
  def build(text, denotations)
    ds = normalize(denotations)
    valid = ds.select { |d| d["span"].is_a?(Hash) && d["span"]["begin"] && d["span"]["end"] }

    unique_urls  = valid.map { |d| d["obj"].to_s }.reject(&:empty?).uniq
    entity_types = unique_urls.map { |url| { "id" => url, "label" => short_id(url) } }

    {
      "text" => text.to_s,
      "denotations" => valid,
      "config" => { "entity types" => entity_types }
    }
  end

  # Derive a short label from a URL/CURIE. Last path segment for URLs
  # (`.../obo/UBERON_0000019` → `UBERON_0000019`); the string itself if no
  # path separator is present (e.g. `MONDO:0004992`).
  def short_id(url)
    seg = url.to_s.rpartition("/").last
    seg.presence || url.to_s
  end

  private

  def normalize(denotations)
    denotations.map do |d|
      h = d.respond_to?(:transform_keys) ? d.transform_keys(&:to_s) : d
      h["span"] = h["span"].transform_keys(&:to_s) if h["span"].is_a?(Hash) && !h["span"].keys.all?(String)
      h
    end
  end
end
