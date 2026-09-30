#!/usr/bin/env python3
"""Tests for tool/validate_ops.py's contract overlay (no network).

Run: python -m unittest discover -s tool -p "test_*.py"
"""
import contextlib
import copy
import io
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_ops as v  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fixtures', 'validate_ops')

OPERATION = """
query Things($k: HmKind) {
  hmThings(pageSize: 5, kind: $k) {
    items {
      code
      seller { name }
      products { sku ... on BundleProduct { dynamic_sku hm_seller { name } } }
    }
  }
  products(filter: { sku: { eq: "a" } }) { items { sku hm_seller { name } } }
}
mutation Save { hmSaveThing(input: { code: "x" }) { code } }
"""


def live_schema():
    with open(os.path.join(FIXTURES, 'live_schema.json'), encoding='utf-8') as f:
        return json.load(f)


def overlay():
    with open(os.path.join(FIXTURES, 'overlay.graphql'), encoding='utf-8') as f:
        return v.parse_sdl(f.read())


def field_names(types, name):
    return [f['name'] for f in (types[name].get('fields') or [])]


def sdl_schema():
    """live_schema.json's twin, read the way --schema-file reads an SDL."""
    with open(os.path.join(FIXTURES, 'live_schema.graphql'), encoding='utf-8') as f:
        return v.schema_from_sdl(f.read())


def run(schema, merge):
    types, qroot, mroot = v.index_schema(copy.deepcopy(schema))
    if merge:
        v.merge_sdl(types, overlay())
    ops, frags = v.P(v.tokenize(OPERATION)).document()
    problems, n_ops = v.validate(types, qroot, mroot, [('x.dart', ops, frags)], frags, root='')
    return problems, n_ops


class ParseSdlTest(unittest.TestCase):
    def test_reads_definitions_and_skips_directives(self):
        defs = {(d['kind'], d['name']): d for d in overlay()}
        query = defs[('OBJECT', 'Query')]
        self.assertEqual([f['name'] for f in query['fields']], ['hmThings'])
        self.assertEqual([a['name'] for a in query['fields'][0]['args']], ['pageSize', 'kind'])
        self.assertEqual(v.named(query['fields'][0]['type']), 'HmThingPage')
        self.assertEqual(query['fields'][0]['type']['kind'], 'NON_NULL')
        self.assertEqual([e['name'] for e in defs[('ENUM', 'HmKind')]['enumValues']], ['ONE', 'TWO'])
        self.assertEqual([i['name'] for i in defs[('INPUT_OBJECT', 'HmThingInput')]['inputFields']],
                         ['code', 'size'])
        self.assertEqual([f['name'] for f in defs[('INTERFACE', 'ProductInterface')]['fields']], ['hm_seller'])

    def test_the_real_contract_parses(self):
        with open(v.DEFAULT_SDL, encoding='utf-8') as f:
            names = {d['name'] for d in v.parse_sdl(f.read())}
        self.assertTrue({'Query', 'Mutation', 'HmAppConfig', 'HmHomeSection', 'HmLinkType',
                         'ProductInterface', 'CartItemInterface', 'OrderItemInterface'} <= names)


class MergeSdlTest(unittest.TestCase):
    def setUp(self):
        self.types, _, _ = v.index_schema(live_schema())
        self.result = v.merge_sdl(self.types, overlay())

    def test_existing_types_gain_fields_and_keep_theirs(self):
        self.assertEqual(field_names(self.types, 'Query'), ['products', 'hmThings'])
        self.assertEqual(field_names(self.types, 'Mutation'), ['ping', 'hmSaveThing'])
        items = {f['name']: f for f in self.types['Products']['fields']}['items']
        self.assertEqual(items['type']['kind'], 'LIST')  # not replaced by the overlay's String

    def test_new_types_enums_and_inputs_are_added(self):
        self.assertEqual(sorted(self.result['types']),
                         ['HmKind', 'HmSeller', 'HmThing', 'HmThingInput', 'HmThingPage'])
        self.assertEqual(self.types['HmKind']['kind'], 'ENUM')
        self.assertEqual(self.types['HmThingInput']['kind'], 'INPUT_OBJECT')
        self.assertEqual([f['name'] for f in self.types['HmThingInput']['inputFields']], ['code', 'size'])

    def test_repeated_declarations_merge(self):
        self.assertEqual(field_names(self.types, 'HmThing'), ['code', 'products', 'seller'])

    def test_interface_fields_reach_every_implementation(self):
        for name in ('ProductInterface', 'SimpleProduct', 'BundleProduct'):
            self.assertIn('hm_seller', field_names(self.types, name), name)
        self.assertIn('BundleProduct.hm_seller', self.result['fields'])
        self.assertIn('dynamic_sku', field_names(self.types, 'BundleProduct'))


class ValidateTest(unittest.TestCase):
    def test_contract_operations_are_clean_on_the_overlay(self):
        problems, n_ops = run(live_schema(), merge=True)
        self.assertEqual(problems, [])
        self.assertEqual(n_ops, 2)

    def test_live_only_reports_what_the_server_lacks(self):
        problems, _ = run(live_schema(), merge=False)
        self.assertIn('x.dart [query Things]: Query.hmThings does not exist', problems)
        self.assertIn('x.dart [query Things]: ProductInterface.hm_seller does not exist', problems)
        self.assertIn('x.dart [mutation Save]: Mutation.hmSaveThing does not exist', problems)

    def test_main_prints_the_mode_and_fails_only_when_lacking(self):
        ops, frags = v.P(v.tokenize(OPERATION)).document()
        collected = ([('x.dart', ops, frags)], frags, [], 1)
        cases = (
            (['--sdl', os.path.join(FIXTURES, 'overlay.graphql')],
             'overlay.graphql (5 types, ', 0),
            (['--live-only'], 'mode: live only (', 1),
        )
        for argv, expected_mode, expected_exit in cases:
            out = io.StringIO()
            with mock.patch.object(v, 'fetch_schema', return_value=live_schema()), \
                    mock.patch.object(v, 'collect', return_value=collected), \
                    contextlib.redirect_stdout(out):
                code = v.main(argv)
            self.assertIn(expected_mode, out.getvalue())
            self.assertEqual(code, expected_exit, out.getvalue())


class SchemaFileTest(unittest.TestCase):
    """--schema-file: the base schema from an SDL file, without the network."""

    def test_an_sdl_validates_like_its_introspection(self):
        for merge in (True, False):
            self.assertEqual(run(sdl_schema(), merge), run(live_schema(), merge), f'merge={merge}')

    def test_roots_interfaces_and_inputs(self):
        schema = sdl_schema()
        self.assertEqual(schema['queryType'], {'name': 'Query'})
        self.assertEqual(schema['mutationType'], {'name': 'Mutation'})
        types, _, _ = v.index_schema(schema)
        self.assertEqual([t['name'] for t in types['ProductInterface']['possibleTypes']],
                         ['SimpleProduct', 'BundleProduct'])
        self.assertEqual([a['name'] for a in field_names_args(types, 'Query', 'products')],
                         ['filter', 'pageSize'])
        self.assertEqual([i['name'] for i in types['ProductAttributeFilterInput']['inputFields']], ['sku'])

    def test_a_schema_block_names_the_roots(self):
        schema = v.schema_from_sdl('schema { query: Root mutation: Change }\n'
                                   'type Root { a: Int }\ntype Change { b: Int }\n')
        self.assertEqual(schema['queryType'], {'name': 'Root'})
        self.assertEqual(schema['mutationType'], {'name': 'Change'})
        self.assertIsNone(v.schema_from_sdl('type Query { a: Int }')['mutationType'])

    def test_the_committed_schema_loads(self):
        with open(os.path.join(v.ROOT, 'lib', 'core', 'graphql', 'schema.graphql'), encoding='utf-8') as f:
            types, qroot, mroot = v.index_schema(v.schema_from_sdl(f.read()))
        self.assertEqual((qroot, mroot), ('Query', 'Mutation'))
        self.assertIn('products', field_names(types, 'Query'))
        self.assertIn('placeOrder', field_names(types, 'Mutation'))
        self.assertIn('SimpleProduct', [t['name'] for t in types['ProductInterface']['possibleTypes']])

    def test_main_reads_the_file_and_never_the_network(self):
        ops, frags = v.P(v.tokenize(OPERATION)).document()
        collected = ([('x.dart', ops, frags)], frags, [], 1)
        schema_file = os.path.join(FIXTURES, 'live_schema.graphql')
        cases = (
            (['--schema-file', schema_file, '--sdl', os.path.join(FIXTURES, 'overlay.graphql')],
             'mode: schema file (', 0),
            (['--schema-file', schema_file, '--live-only'], 'mode: schema file only (', 1),
        )
        for argv, expected_mode, expected_exit in cases:
            out = io.StringIO()
            with mock.patch.object(v, 'fetch_schema', side_effect=AssertionError('network used')), \
                    mock.patch.object(v, 'collect', return_value=collected), \
                    contextlib.redirect_stdout(out):
                code = v.main(argv)
            self.assertIn(expected_mode, out.getvalue())
            self.assertEqual(code, expected_exit, out.getvalue())


def field_names_args(types, type_name, field):
    return {f['name']: f for f in types[type_name]['fields']}[field]['args']


if __name__ == '__main__':
    unittest.main()
