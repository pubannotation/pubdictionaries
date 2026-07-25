# frozen_string_literal: true

require "rails_helper"

RSpec.describe SiafSource do
  describe ".short_id" do
    it "returns the last path segment of a URL" do
      expect(described_class.short_id("http://purl.obolibrary.org/obo/UBERON_0000019")).to eq("UBERON_0000019")
    end

    it "returns CURIE-style IDs (no path separator) unchanged" do
      expect(described_class.short_id("MONDO:0004992")).to eq("MONDO:0004992")
    end

    it "handles a trailing slash gracefully (returns empty last segment as-is)" do
      # rpartition('/').last returns "" for "http://x/"; presence-fallback
      # yields the original URL rather than an empty label.
      expect(described_class.short_id("http://example.com/")).to eq("http://example.com/")
    end
  end

  describe ".build" do
    let(:text) { "The eye is connected to the brain." }
    let(:denotations) do
      [
        { "span" => { "begin" => 4, "end" => 7 },  "obj" => "http://x/UBERON_0000019" },
        { "span" => { "begin" => 28, "end" => 33 }, "obj" => "http://x/UBERON_0000955" }
      ]
    end

    it "returns a hash with text/denotations/config keys ready for SimpleInlineTextAnnotation.generate" do
      out = described_class.build(text, denotations)
      expect(out.keys).to match_array(%w[text denotations config])
      expect(out["text"]).to eq(text)
      expect(out["denotations"]).to eq(denotations)
    end

    it "builds entity_types with { id: <URL>, label: <short> } for each unique URL" do
      out = described_class.build(text, denotations)
      types = out["config"]["entity types"]
      expect(types).to match_array([
        { "id" => "http://x/UBERON_0000019", "label" => "UBERON_0000019" },
        { "id" => "http://x/UBERON_0000955", "label" => "UBERON_0000955" }
      ])
    end

    it "deduplicates URLs in entity_types when the same obj appears on multiple denotations" do
      dupes = [
        { "span" => { "begin" => 0, "end" => 3 }, "obj" => "http://x/A" },
        { "span" => { "begin" => 4, "end" => 7 }, "obj" => "http://x/A" }
      ]
      types = described_class.build("aaa bbb", dupes)["config"]["entity types"]
      expect(types.length).to eq(1)
      expect(types.first["id"]).to eq("http://x/A")
    end

    it "drops denotations with malformed/absent span fields (defensive: gem crashes on nil span)" do
      mixed = denotations + [
        { "obj" => "http://x/NO_SPAN" },                                # no span key
        { "span" => { "begin" => nil, "end" => 10 }, "obj" => "http://x/PARTIAL" }
      ]
      out = described_class.build(text, mixed)
      expect(out["denotations"]).to eq(denotations)   # malformed entries filtered out
      # Their URLs also don't appear in entity_types.
      expect(out["config"]["entity types"].map { |e| e["id"] }).not_to include("http://x/NO_SPAN", "http://x/PARTIAL")
    end

    it "accepts symbol-keyed denotations (from annotator direct output)" do
      # The controller path receives string keys (JSON parse); the view path
      # receives symbol keys straight from TextAnnotator. Both must work.
      sym = [ { span: { begin: 4, end: 7 }, obj: "http://x/UBERON_0000019" } ]
      out = described_class.build(text, sym)
      expect(out["denotations"].first["span"]).to eq({ "begin" => 4, "end" => 7 })
      expect(out["denotations"].first["obj"]).to eq("http://x/UBERON_0000019")
    end
  end

  describe "round-trip via SimpleInlineTextAnnotation.generate" do
    # Composition sanity check — the value of this service is that its output
    # feeds the gem cleanly and produces the SIAF we expect end-to-end.
    it "produces SIAF text with pipe-joined multi-label + tail reference block" do
      text = "The eye and brain."
      denotations = [
        { "span" => { "begin" => 4, "end" => 7 },  "obj" => "http://x/UBERON_0000019" },
        { "span" => { "begin" => 12, "end" => 17 }, "obj" => "http://x/UBERON_0000955" },
        { "span" => { "begin" => 12, "end" => 17 }, "obj" => "http://x/UBERON_6110636" }
      ]

      out = SimpleInlineTextAnnotation.generate(SiafSource.build(text, denotations))

      expect(out).to include("[eye][UBERON_0000019]")
      expect(out).to include("[brain][UBERON_0000955|UBERON_6110636]")
      expect(out).to include("[UBERON_0000019]: http://x/UBERON_0000019")
      expect(out).to include("[UBERON_0000955]: http://x/UBERON_0000955")
      expect(out).to include("[UBERON_6110636]: http://x/UBERON_6110636")
    end
  end
end
