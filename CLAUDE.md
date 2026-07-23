# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PubDictionaries is a Rails 8 platform where users share dictionaries (collections of terms → identifiers) and use them to automatically annotate free text. Ruby 3.4.4. The core value is in the **annotation/lookup pipeline**, which combines three independent matching strategies over external search infrastructure.

## External service dependencies

The app does not run standalone — it requires four backing services (see `compose.yml` for the canonical wiring):

- **PostgreSQL with pgvector** (`ankane/pgvector` image) — primary DB *and* the vector store for semantic search (the `neighbor` gem + `vector(768)` columns + HNSW indexes).
- **Elasticsearch 7.x** with the ICU, Kuromoji (Japanese), and Nori (Korean) analysis plugins — used purely as a **text analyzer/normalizer**, not as the primary term store. See `elasticsearch/` for the custom image and `config/elasticsearch.yml`.
- **Redis + Sidekiq** — all heavy work (compile, import, embeddings, annotation) is async.
- **Embedding server** — an Ollama-style HTTP service at `http://localhost:11435/api/embed`, default model `pubmedbert`. Required for any embedding/semantic feature. Configured in `config/initializers/embedding_server.rb`.

DB connection is env-driven (`DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`); see `config/database.yml`. OAuth/reCAPTCHA secrets go in `.env` (copy from `.env.example`); see README.md for the Google OAuth and reCAPTCHA setup procedure.

`lib/simstring` is a **git submodule** (github.com/pubannotation/simstring) — run `git submodule update --init` after cloning.

## Common commands

Docker (recommended — brings up all services):

```sh
docker compose build
docker compose up                    # web on :3000
```

Local (services must already be running):

```sh
bundle
bin/rails db:create db:migrate
bin/rails runner script/create_index.rb   # create the Elasticsearch index — required before annotation works
bin/rails s
```

Dev helper scripts: `./start-service-dev.sh` (clobbers assets, runs web on :3001), `./start-sidekiq-dev.sh` (Sidekiq with `config/sidekiq.yml`).

### Tests

This project uses **RSpec**, not Minitest — ignore the `bin/rails test` line in README.md.

```sh
bundle exec rspec                                   # full suite
bundle exec rspec spec/jobs/compile_job_spec.rb     # one file
bundle exec rspec spec/path/to/file_spec.rb:42      # single example by line
bundle exec rspec --only-failures                   # rerun last failures
docker compose run --rm web bundle exec rspec       # under docker
```

RSpec records run state in `spec/examples.txt` (gitignored — do not re-add it to git).

## Architecture

### Domain model (`app/models/`)

- **Dictionary** — owns **Entry**, **Pattern**, **Tag**, **Job**, and **Association** (extra non-owner managers). It is the unit of search and carries the per-dictionary SimString DB and semantic table. Visibility/permission scopes: `.visible`, `.editable`, `.administrable`, `.mine`.
- **Entry** — a term. Has an `EntryMode`: GRAY (0, imported/unreviewed), WHITE (1, approved), BLACK (2, excluded), AUTO_EXPANDED (6). Scopes `.gray/.white/.black/.active`. Only WHITE entries feed the compiled SimString DB. Carries an `embedding` vector for semantic search.
- **User** — Devise auth. Authorization is the integer `user_level`, **not** a boolean: REGULAR (0), EXPERT (1), ADMIN (9), with `regular?/expert?/admin?` helpers. (The old `admin` boolean was removed — don't reintroduce it.)
- **Job** — tracks every async task with status (waiting→running→finished/error), progress (`num_items`/`num_dones`), ETR estimation, and a file-flag suspension mechanism.

### The annotation/lookup pipeline (the heart of the app)

Text annotation (`app/controllers/annotation_controller.rb` → `app/models/text_annotator.rb`, `text_annotator_sem.rb`):

1. Text is tokenized/normalized via the **Elasticsearch** `_analyze` endpoint (language-specific analyzers; `Net::HTTP::Persistent` connection).
2. Candidate spans (1–5 tokens) are extracted and filtered (no_term/no_begin/no_end words).
3. Each span is matched against `Dictionary#search_term` using three strategies, scored 0–1:
   - **Exact** — score 1.0, direct label match.
   - **Surface** — fuzzy n-gram similarity via the **SimString** DB stored at `db/simstring/{dictionary}/` (n-gram order varies by language; built by `CompileJob`).
   - **Semantic** — cosine distance over embeddings via **pgvector + HNSW**, against either a persistent `semantic_dict_{id}` table or a per-request temp table. Batched (≈500/batch) with parallel threads.

Annotation HTTP surfaces: synchronous `/text_annotation`; fire-and-forget `/annotation_request` (webhook callback); job-tracked `/annotation_tasks` → poll `/annotation_tasks/:id` → fetch `/annotation_results/:filename`.

Lookup (`app/controllers/lookup_controller.rb`) exposes the same matching without span detection: `/find_ids` (labels→ids), `/find_terms` (ids→labels), `/prefix_completion`, `/substring_completion`, `/mixed_completion`. These also exist as per-dictionary member routes.

### Background jobs (`app/jobs/`)

All jobs include `concerns/use_job_record_concern.rb`, which creates/updates the **Job** record around enqueue/perform and captures errors. Sidekiq queues (`config/sidekiq.yml`, concurrency 25): `upload`, `general`, `annotation`.

- **CompileJob** — rebuilds the SimString DB from WHITE entries; refreshes stop words. Run after entry changes for surface matching to reflect them.
- **LoadEntriesFromFileJob** — CSV/TSV import, batched (~10k), with normalization.
- **UpdateDictionaryEmbeddingsJob** — fetches embeddings from the embedding server, bulk-upserts into the semantic table, removes outliers, writes a report into `Job.metadata`/`Dictionary.embedding_report`.
- **CreateSemanticTablesJob** — builds the persistent `semantic_dict_{id}` HNSW table.
- **TextAnnotationJob**, **CreateDownloadableJob**, **ExpandSynonymJob**.

### API & MCP

- **REST** `app/controllers/api/v1/` — token-authenticated entry management (`entries#create/destroy/upload_tsv/undo`) and `jobs#destroy`.
- **MCP** `app/controllers/mcp_controller.rb` — a JSON-RPC 2.0 / streamable-HTTP Model Context Protocol server at `/mcp`. Tools: `list_dictionaries`, `get_dictionary_description`, `find_ids`, `search`, `find_terms`. These are thin wrappers that re-issue internal HTTP requests to the lookup endpoints, so MCP behavior changes when lookup changes.

### Search infrastructure notes

- The SimString DB is a file-based artifact under `db/simstring/` (gitignored), regenerated by `CompileJob` — it is *not* automatically in sync with the DB; entry edits require a recompile to affect surface matching.
- Semantic tables come in two forms (persistent `semantic_dict_{id}` vs. per-request temp); both use the same `ORDER BY embedding <=> query` LATERAL query bounded by a distance threshold.
- Elasticsearch holds no authoritative data — reindexing (`script/create_index.rb`) is safe and sometimes necessary after analyzer/config changes.

### Tests (`spec/`)

RSpec + FactoryBot. Layout: `spec/{controllers,models,jobs,lib,views,factories,support}`. `spec/support/` wires FactoryBot and Devise helpers; `spec/rails_helper.rb` uses transactional, factory-based fixtures. Slowest 10 examples are profiled (`config.profile_examples`).
