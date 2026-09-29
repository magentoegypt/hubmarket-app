#!/usr/bin/env node
// Convert a GraphQL introspection JSON (the raw output of tool/introspect.sh)
// into SDL — lib/core/graphql/schema.graphql — for graphql_codegen.
//
// Uses the official `graphql` package (buildClientSchema → printSchema) so the
// result is a correct, canonical schema. lexicographicSortSchema makes the
// output deterministic, so re-running only diffs when the live schema changes.
//
// Usage: node tool/json_to_sdl.mjs [in.json] [out.graphql]
//   defaults: lib/core/graphql/schema.introspection.json → .../schema.graphql
import { readFileSync, writeFileSync } from 'node:fs';
import { buildClientSchema, lexicographicSortSchema, printSchema } from 'graphql';

const inFile = process.argv[2] ?? 'lib/core/graphql/schema.introspection.json';
const outFile = process.argv[3] ?? 'lib/core/graphql/schema.graphql';

const raw = JSON.parse(readFileSync(inFile, 'utf8'));
// Accept either the full GraphQL response ({data:{__schema}}) or just the data.
const introspection = raw.__schema ? raw : raw.data;
if (!introspection || !introspection.__schema) {
  console.error(`✖ ${inFile} is not a valid introspection result (no __schema).`);
  if (raw.errors) console.error(JSON.stringify(raw.errors, null, 2));
  process.exit(1);
}

const schema = lexicographicSortSchema(buildClientSchema(introspection));
const sdl = printSchema(schema).replace(/\s+$/, '') + '\n';
writeFileSync(outFile, sdl);
console.log(`Wrote ${outFile} (${sdl.length} bytes of SDL)`);
