# AGENTS.md

<purpose>
This repository contains the technical documentation for MiPIT-PoC: OpenAPI specification, Architectural Decision Records, message contracts, payment status state machine, error codes, field mappings, routing rules, demo runbooks, and architectural overviews.

It is responsible for:
- OpenAPI 3.1 specification for mipit-core API (openapi/openapi.yaml),
- 8 Architectural Decision Records (adrs/),
- RabbitMQ message contracts (contracts/rabbitmq-messages.md),
- Payment status state machine (contracts/payment-status-machine.md),
- Error code catalog (contracts/error-codes.md),
- Field mapping tables: PIX↔Canonical, SPEI↔Canonical (mappings/*.csv),
- Routing rule definitions (route-rules/),
- Demo runbooks for local and VM environments (demo-runbook/),
- Architecture overview and design documents (design/),
- Evidence placeholders for test results and screenshots (evidence/).

Treat this documentation as a reference that supports — but does not override — the actual implementations in other repos.
When docs and code disagree, the code repos are the source of truth.
</purpose>

<project_scope>
This repo is documentation only — no executable code.
It serves as the reference library for the PoC architecture, contracts, and demo procedures.
Placeholders exist for PDFs (SRS, SPMP, propuesta) and diagram PNGs that must be added manually.
</project_scope>

<instruction_priority>
- User instructions override default style, tone, and initiative preferences.
- Safety, honesty, privacy, and permission constraints do not yield.
</instruction_priority>

<workflow>
  <phase name="clarify">
  - Before changes, clarify: which document type? (OpenAPI, ADR, contract, mapping, runbook, design)
  - Does the change reflect an actual implementation change or a planned future change?
  </phase>

  <phase name="research">
  - Cross-reference with the actual implementation in mipit-core, adapters, and infra repos.
  - Verify that OpenAPI spec matches actual API endpoints and response shapes.
  - Verify mapping CSVs match actual mapping_table seeds in mipit-infra.
  - Verify routing rules match actual route_rules seeds.
  </phase>

  <phase name="implement">
  - Keep OpenAPI spec complete and accurate — it should be usable with Swagger UI.
  - Keep ADRs in standard format (Title, Status, Context, Decision, Consequences).
  - Keep contracts precise: message formats, status transitions, error codes should match code.
  - Keep mapping CSVs aligned with the DB seed data and translation functions.
  - Keep runbooks executable: a reader should be able to follow them step by step.
  </phase>

  <phase name="verify">
  - Verify OpenAPI spec parses without errors (use a validator).
  - Verify runbook steps against actual docker compose setup.
  - Verify status machine covers all 11 statuses and valid transitions.
  </phase>
</workflow>

<documentation_rules>
- OpenAPI is the contract of record for the mipit-core API.
- ADRs document architectural decisions and should not be modified after acceptance (add new ADRs instead).
- Mapping CSVs have columns: source_field, target_field, transformation, validation, notes.
- Status machine has 11 states: RECEIVED, VALIDATED, CANONICALIZED, NORMALIZED, ROUTED, TRANSLATED, QUEUED, SENT_TO_DESTINATION, ACKED_BY_RAIL, COMPLETED, FAILED, REJECTED, DUPLICATE.
- Error codes are organized: API errors (MIPIT-4xx), Internal errors (MIPIT-5xx), Rail-specific (PIX-xxx, SPEI-xxx).
- Demo runbooks target two environments: local Docker Compose and 3-VM deployment.
</documentation_rules>

<default_commands>
- No build commands — this is a documentation repository.
- Validate OpenAPI: use an online validator or `npx @redocly/cli lint openapi/openapi.yaml`
</default_commands>
