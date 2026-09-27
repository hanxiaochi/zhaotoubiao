# Enterprise AI Workflow and Audit Platform

## Executive summary

This repository demonstrates a production-oriented internal platform for professional-services teams that manage projects, evidence, approvals, OCR, AI-assisted review, deadlines, fees and audit history.

It is not a static dashboard. The inspectable implementation includes persistent business records, role and project isolation, controlled file access, background work, human approval gates, evidence exports, recovery procedures and automated tests. All public screenshots and repository data are synthetic.

## Business problem

Professional-services workflows often begin in spreadsheets, shared folders and chat messages. That creates recurring operational risks:

- unclear ownership and deadlines;
- inconsistent review and approval paths;
- weak links between conclusions and source evidence;
- files shared beyond the correct project or role;
- AI output applied without human review;
- incomplete audit history and difficult recovery;
- fee and collection data separated from delivery status.

The goal was to turn those fragmented activities into one reviewable operating system while preserving human responsibility for professional conclusions.

## Delivered system

The current implementation includes:

- first-run administrator setup without a universal default password;
- departments, users, roles, project membership and least-privilege access;
- project intake, asset records, claim materials and multi-stage review;
- file hashing, controlled downloads, OCR, source locations and confidence evidence;
- tender templates, bid-analysis workflows, qualification evidence and deadlines;
- AI-assisted analysis with recorded input scope, human approval and safe failure;
- workflow tasks, notifications, immutable audit events and version history;
- fee ledgers, filtered reporting, CSV export and read-only detail views;
- deployment, operations, recovery, security and release-gate documentation.

## Architecture

| Layer | Implementation |
| --- | --- |
| Application | Rails 8.1 modular monolith on Ruby 3.4 |
| Web UI | Hotwire, Turbo, Stimulus and Tailwind |
| Data | SQLite for local development and tests; PostgreSQL production design |
| Files | Active Storage with S3-compatible object-storage support |
| Background work | Solid Queue in production; bounded development behavior |
| OCR | Separate Python worker for Chinese OCR and page-level extraction |
| AI integration | OpenAI-compatible adapter with explicit input limits and human approval |
| Operations | Health checks, deployment guides, backup, restore and release gates |

See [Architecture](ARCHITECTURE.md), [Deployment](DEPLOYMENT.md), [Operations](OPERATIONS.md) and [Security](SECURITY.md) for implementation details.

## Evidence a buyer can inspect

- request, service, model, job and JavaScript tests under `spec/`;
- synthetic-data screenshots under [`docs/screenshots`](screenshots/);
- requirement traceability and explicit release gates;
- local acceptance records that separate passing checks from open items;
- SQLite and PostgreSQL test paths documented in the repository;
- owner-cloud deployment configuration with a clear HTTP-only demo boundary;
- no real API key, customer attachment, private environment file or production database in the public source.

The main screenshot set covers claim review, OCR evidence, asset history, bid analysis, task assignment, AI input scope and fee-ledger workflows.

## Delivery role

Han Xiaochi led the translation of operational requirements into system boundaries, workflows, permissions, audit evidence, deployment controls and acceptance records. The delivery approach combines production-operations judgement with AI-assisted engineering and human verification.

For a customer engagement, Han remains accountable for discovery, delivery risk, operational design, acceptance and communication. Additional full-stack engineers or named specialists are added only after scope, availability and responsibilities are confirmed.

## What this proves

This repository is evidence that a complex internal workflow can be turned into a working, inspectable application with backend persistence, permissions, auditability, tests and operational documentation.

It supports discussions about:

- internal business platforms;
- approval and audit workflows;
- document and evidence processing;
- AI-assisted review with human control;
- legacy spreadsheet or shared-folder modernisation;
- bounded web-application delivery and operational handover.

## What it does not prove

The repository does not claim completed customer-cloud acceptance, production capacity, formal compliance certification or finished rules for professional domains whose source requirements were not provided.

The following remain environment-specific acceptance work:

- target Linux host and managed PostgreSQL installation;
- HTTPS, DNS, private object storage and secret management;
- production monitoring, backup and restore drills;
- customer data migration and role mapping;
- load, capacity and failure testing in the named environment;
- legal, accounting, valuation or industry-rule approval by qualified owners.

## Suitable first engagement

A similar project should begin with paid discovery and one end-to-end vertical slice. The first acceptance should cover one real workflow from intake through permissions, persistence, review, audit history and export before the remaining modules are priced or scheduled.

For commercial enquiries, use the repository owner profile and include the workflow, user roles, existing data, required integrations, deployment environment, timeline and acceptance expectations.
