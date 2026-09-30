#!/usr/bin/env python3
"""Validate every GraphQL operation in the app against the Magento schema.

Finds operations in `.graphql` files and in Dart string literals (inline
`query`/`mutation`/`fragment` documents), then checks every selected field,
argument, inline-fragment type and fragment spread against the schema of the
backend. Nothing is executed on the server — introspection only.

Two modes:

* default — the live introspection **plus** the Hub Market App contract
  (`lib/core/graphql/hubapp.graphql`, the deployed HubApp contract), merged the way Magento
  merges module schemas: a `type X` / `interface X` that already exists adds
  its fields, fields added to an interface also land on every type that
  implements it, and new types, enums and inputs are added;
* `--live-only` — only what the server supports today.

`--schema-file PATH` reads the base schema from an SDL file instead of
introspecting the endpoint — offline, e.g. in CI against the committed
`lib/core/graphql/schema.graphql` (refreshed by `tool/introspect_to_sdl.py`).
Both modes work on it.

Usage:
  python tool/validate_ops.py [endpoint] [--live-only] [--sdl PATH] [--schema-file PATH]
      (default endpoint: Hub Market live GraphQL)
Exit code 1 when any operation references something the schema doesn't have.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

DEFAULT_ENDPOINT = 'https://hub-market.magento2.click/graphql'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SDL = os.path.join(ROOT, 'lib', 'core', 'graphql', 'hubapp.graphql')

# Type-system files, never operation documents.
SCHEMA_FILES = {'schema.graphql', 'hubapp.graphql'}

INTROSPECTION = """{ __schema { queryType { name } mutationType { name }
 types { kind name fields(includeDeprecated: true) { name args { name } type { ...R } }
 inputFields { name } possibleTypes { name } } } }
fragment R on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }"""


def fetch_schema(endpoint):
    """The live `__schema` (introspection only)."""
    req = urllib.request.Request(endpoint, data=json.dumps({'query': INTROSPECTION}).encode(),
                                 headers={'Content-Type': 'application/json', 'User-Agent': 'HubMarketApp-validate'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)['data']['__schema']


def index_schema(schema):
    """(types by name, query root name, mutation root name)."""
    types = {t['name']: t for t in schema['types']}
    return types, schema['queryType']['name'], (schema.get('mutationType') or {}).get('name')


def named(t):
    while t.get('ofType'):
        t = t['ofType']
    return t['name']


# ---------------------------------------------------------------- tokenizer
TOKEN = re.compile(r'''
  (?P<ws>[\s,]+|\#[^\n]*) |
  (?P<block>"""(?:\\"""|[^"]|"(?!""))*""") |
  (?P<str>"(?:\\.|[^"\\])*") |
  (?P<spread>\.\.\.) |
  (?P<punct>[{}()\[\]:!$=@|&]) |
  (?P<num>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?) |
  (?P<name>[_A-Za-z][_0-9A-Za-z]*)
''', re.X)


def tokenize(src):
    out, i = [], 0
    while i < len(src):
        m = TOKEN.match(src, i)
        if not m:
            raise SyntaxError(f'unexpected {src[i:i + 20]!r}')
        i = m.end()
        if m.lastgroup != 'ws':
            out.append((m.lastgroup, m.group()))
    return out


class P:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, val=None):
        tok = self.peek()
        if tok[0] is None:
            raise SyntaxError('unexpected end of document')
        if val is not None and tok[1] != val:
            raise SyntaxError(f'expected {val!r} got {tok[1]!r}')
        self.i += 1
        return tok

    def skip_value(self):
        k, v = self.take()
        if v in ('[', '{'):
            close = ']' if v == '[' else '}'
            while self.peek()[1] != close:
                if v == '{':
                    self.take()          # name
                    self.take(':')
                self.skip_value()
            self.take(close)
        elif v == '$':
            self.take()

    def args(self):
        names = []
        if self.peek()[1] == '(':
            self.take('(')
            while self.peek()[1] != ')':
                names.append(self.take()[1])
                self.take(':')
                self.skip_value()
            self.take(')')
        return names

    def directives(self):
        while self.peek()[1] == '@':
            self.take('@')
            self.take()
            self.args()

    def var_defs(self):
        if self.peek()[1] == '(':
            depth = 0
            while True:
                v = self.take()[1]
                depth += v == '('
                depth -= v == ')'
                if depth == 0:
                    break

    def selection_set(self):
        sel = []
        self.take('{')
        while self.peek()[1] != '}':
            if self.peek()[0] == 'spread':
                self.take()
                if self.peek()[1] == 'on':
                    self.take()
                    tname = self.take()[1]
                    self.directives()
                    sel.append(('inline', tname, self.selection_set()))
                elif self.peek()[1] == '{' or self.peek()[1] == '@':
                    self.directives()
                    sel.append(('inline', None, self.selection_set()))
                else:
                    sel.append(('spread', self.take()[1]))
                    self.directives()
                continue
            name = self.take()[1]
            if self.peek()[1] == ':':
                self.take(':')
                name = self.take()[1]
            a = self.args()
            self.directives()
            sub = self.selection_set() if self.peek()[1] == '{' else None
            sel.append(('field', name, a, sub))
        self.take('}')
        return sel

    def document(self):
        ops, frags = [], {}
        while self.peek()[0]:
            k, v = self.peek()
            if v == '{':
                ops.append(('query', 'anonymous', self.selection_set()))
            elif v in ('query', 'mutation', 'subscription'):
                self.take()
                name = self.take()[1] if self.peek()[0] == 'name' else 'anonymous'
                self.var_defs()
                self.directives()
                ops.append((v, name, self.selection_set()))
            elif v == 'fragment':
                self.take()
                name = self.take()[1]
                self.take('on')
                tname = self.take()[1]
                self.directives()
                frags[name] = (tname, self.selection_set())
            else:
                raise SyntaxError(f'unexpected top-level token {v!r}')
        return ops, frags


# ---------------------------------------------------------------- SDL overlay
SDL_KINDS = {'type': 'OBJECT', 'interface': 'INTERFACE', 'input': 'INPUT_OBJECT',
             'enum': 'ENUM', 'union': 'UNION', 'scalar': 'SCALAR'}


class SdlParser(P):
    """Reads the type definitions of an SDL document into introspection-shaped
    dicts. Directives (`@doc`, `@resolver`, `@cache`, …), descriptions and
    default values are skipped; `schema` and `directive` definitions are
    ignored."""

    def descriptions(self):
        while self.peek()[0] in ('str', 'block'):
            self.take()

    def type_ref(self):
        if self.peek()[1] == '[':
            self.take('[')
            inner = self.type_ref()
            self.take(']')
            ref = {'kind': 'LIST', 'name': None, 'ofType': inner}
        else:
            ref = {'kind': None, 'name': self.take()[1], 'ofType': None}
        if self.peek()[1] == '!':
            self.take('!')
            ref = {'kind': 'NON_NULL', 'name': None, 'ofType': ref}
        return ref

    def input_value(self):
        self.descriptions()
        name = self.take()[1]
        self.take(':')
        ref = self.type_ref()
        if self.peek()[1] == '=':
            self.take('=')
            self.skip_value()
        self.directives()
        return {'name': name, 'type': ref}

    def arguments_definition(self):
        args = []
        if self.peek()[1] == '(':
            self.take('(')
            while self.peek()[1] != ')':
                args.append(self.input_value())
            self.take(')')
        return args

    def fields_definition(self):
        fields = []
        if self.peek()[1] != '{':
            return fields
        self.take('{')
        while self.peek()[1] != '}':
            self.descriptions()
            name = self.take()[1]
            args = self.arguments_definition()
            self.take(':')
            ref = self.type_ref()
            self.directives()
            fields.append({'name': name, 'args': [{'name': a['name']} for a in args], 'type': ref})
        self.take('}')
        return fields

    def definitions(self):
        """The type definitions; a `schema { query: … }` block's root types
        land in `self.roots` ({'query': 'Query', …})."""
        defs = []
        self.roots = {}
        while self.peek()[0]:
            self.descriptions()
            keyword = self.take()[1]
            extend = keyword == 'extend'
            if extend:
                keyword = self.take()[1]
            if keyword == 'schema':
                self.directives()
                self.take('{')
                while self.peek()[1] != '}':
                    operation = self.take()[1]
                    self.take(':')
                    self.roots[operation] = self.take()[1]
                self.take('}')
                continue
            if keyword == 'directive':
                self.take('@')
                self.take()
                self.arguments_definition()
                if self.peek()[1] == 'repeatable':
                    self.take()
                self.take('on')
                if self.peek()[1] == '|':
                    self.take('|')
                self.take()
                while self.peek()[1] == '|':
                    self.take('|')
                    self.take()
                continue
            if keyword not in SDL_KINDS:
                raise SyntaxError(f'unexpected SDL keyword {keyword!r}')
            d = {'kind': SDL_KINDS[keyword], 'name': self.take()[1], 'extend': extend,
                 'fields': [], 'inputFields': [], 'enumValues': [], 'interfaces': [], 'members': []}
            if keyword in ('type', 'interface') and self.peek()[1] == 'implements':
                self.take()
                while self.peek()[0] == 'name' or self.peek()[1] == '&':
                    tok = self.take()
                    if tok[1] != '&':
                        d['interfaces'].append(tok[1])
                    if self.peek()[1] in ('{', '@') or self.peek()[0] is None:
                        break
            self.directives()
            if keyword in ('type', 'interface'):
                d['fields'] = self.fields_definition()
            elif keyword == 'input' and self.peek()[1] == '{':
                self.take('{')
                while self.peek()[1] != '}':
                    d['inputFields'].append(self.input_value())
                self.take('}')
            elif keyword == 'enum' and self.peek()[1] == '{':
                self.take('{')
                while self.peek()[1] != '}':
                    self.descriptions()
                    d['enumValues'].append({'name': self.take()[1]})
                    self.directives()
                self.take('}')
            elif keyword == 'union' and self.peek()[1] == '=':
                self.take('=')
                if self.peek()[1] == '|':
                    self.take('|')
                d['members'].append(self.take()[1])
                while self.peek()[1] == '|':
                    self.take('|')
                    d['members'].append(self.take()[1])
            defs.append(d)
        return defs


def parse_sdl(src):
    return SdlParser(tokenize(src)).definitions()


def schema_from_sdl(src):
    """An introspection-shaped `__schema` (what fetch_schema returns) built
    from a whole SDL document, e.g. the committed schema.graphql — the offline
    stand-in for introspection. The root types are the `schema { … }` block's,
    else `Query` and `Mutation`. Interfaces list their implementations as
    `possibleTypes`, unions their members."""
    parser = SdlParser(tokenize(src))
    types = {}
    merge_sdl(types, parser.definitions())
    query = parser.roots.get('query', 'Query')
    mutation = parser.roots.get('mutation', 'Mutation' if 'Mutation' in types else None)
    return {'queryType': {'name': query},
            'mutationType': {'name': mutation} if mutation else None,
            'types': list(types.values())}


def _add_named(items, new, stats, label):
    """Appends the entries of [new] whose name [items] lacks; returns [items]."""
    items = list(items or [])
    have = {x['name'] for x in items}
    for x in new:
        if x['name'] not in have:
            items.append(x)
            have.add(x['name'])
            stats.append(f"{label}.{x['name']}")
    return items


def merge_sdl(types, defs):
    """Overlays SDL definitions on introspected [types] (modified in place),
    the way Magento merges every module's schema.graphqls:

    * a type / interface / input / enum that already exists gains the fields
      (values) it lacks — nothing it has is replaced;
    * fields declared on an interface are added to every type implementing it
      (the live `possibleTypes`, plus SDL types that `implements` it);
    * anything new is added.

    Returns {'types': [...added type names], 'fields': [...added Type.field]}.
    """
    added_types, added_fields = [], []
    sdl_implementers = {}
    for d in defs:
        name = d['name']
        t = types.get(name)
        if t is None:
            t = types[name] = {'kind': d['kind'], 'name': name, 'fields': None,
                               'inputFields': None, 'possibleTypes': None}
            added_types.append(name)
        if d['kind'] in ('OBJECT', 'INTERFACE'):
            t['fields'] = _add_named(t.get('fields'), d['fields'], added_fields, name)
            for iface in d['interfaces']:
                sdl_implementers.setdefault(iface, []).append(name)
        elif d['kind'] == 'INPUT_OBJECT':
            t['inputFields'] = _add_named(t.get('inputFields'), d['inputFields'], added_fields, name)
        elif d['kind'] == 'ENUM':
            t['enumValues'] = _add_named(t.get('enumValues'), d['enumValues'], [], name)
        elif d['kind'] == 'UNION':
            t['possibleTypes'] = _add_named(t.get('possibleTypes'), [{'name': m} for m in d['members']], [], name)
    for iface, impls in sdl_implementers.items():
        t = types.get(iface)
        if t is not None:
            t['possibleTypes'] = _add_named(t.get('possibleTypes'), [{'name': n} for n in impls], [], iface)
    for d in defs:
        if d['kind'] != 'INTERFACE' or not d['fields']:
            continue
        for impl in (types[d['name']].get('possibleTypes') or []):
            target = types.get(impl['name'])
            if target is not None and target.get('fields') is not None:
                target['fields'] = _add_named(target['fields'], d['fields'], added_fields, impl['name'])
    return {'types': added_types, 'fields': added_fields}


# ---------------------------------------------------------------- extraction
DART_STR = re.compile(r"(r?)('''|\"\"\")(.*?)\2", re.S)
LOOKS_GQL = re.compile(r'^\s*(#[^\n]*\n\s*)*(query|mutation|fragment|subscription|\{)\b|^\s*(#[^\n]*\n\s*)*\{', re.S)


def extract(path):
    src = open(path, encoding='utf-8').read()
    if path.endswith('.graphql'):
        return [src]
    docs = []
    for m in DART_STR.finditer(src):
        raw, body = m.group(1) == 'r', m.group(3)
        if not raw:
            # In a non-raw Dart string `$x` / `${...}` is Dart interpolation (shared
            # fragments, optional args) and `\$x` is a GraphQL variable.
            body = re.sub(r'(?<!\\)\$\{[^}]*\}', ' ', body)
            body = re.sub(r'(?<!\\)\$[A-Za-z_]\w*', ' ', body)
            body = body.replace('\\$', '$')
        if LOOKS_GQL.search(body) and re.search(r'\b(query|mutation|fragment)\b|^\s*\{', body):
            docs.append(body)
    return docs


def collect(root, bases=('lib', 'test', 'integration_test')):
    """(parsed [(file, ops, frags)], all fragments, parse errors, file count)."""
    files = []
    for base in bases:
        for dp, dn, fn in os.walk(os.path.join(root, base)):
            for f in fn:
                if f in SCHEMA_FILES or f.endswith('.graphql.dart'):
                    continue
                if f.endswith('.graphql') or f.endswith('.dart'):
                    files.append(os.path.join(dp, f))
    parsed, fragments, parse_errors = [], {}, []
    for f in sorted(files):
        for doc in extract(f):
            try:
                ops, frags = P(tokenize(doc)).document()
            except SyntaxError as e:
                if re.search(r'\b(query|mutation)\s+\w+', doc):
                    parse_errors.append(f'{os.path.relpath(f, root)}: {e}')
                continue
            fragments.update(frags)
            parsed.append((f, ops, frags))
    return parsed, fragments, parse_errors, len(files)


def validate(types, qroot, mroot, parsed, fragments, root=ROOT):
    """(sorted unique problems, operation count)."""
    problems = []

    def check(sel, tname, where, seen=()):
        t = types.get(tname)
        if t is None:
            problems.append(f'{where}: unknown type {tname}')
            return
        fields = {x['name']: x for x in (t.get('fields') or [])}
        for s in sel:
            if s[0] == 'field':
                _, name, args, sub = s
                if name == '__typename':
                    continue
                if name not in fields:
                    problems.append(f'{where}: {tname}.{name} does not exist')
                    continue
                known = {a['name'] for a in fields[name]['args']}
                for a in args:
                    if a not in known:
                        problems.append(f'{where}: {tname}.{name}(arg {a}) does not exist')
                if sub is not None:
                    check(sub, named(fields[name]['type']), where, seen)
            elif s[0] == 'inline':
                check(s[2], s[1] or tname, where, seen)
            elif s[0] == 'spread':
                if s[1] in seen:
                    continue
                fr = fragments.get(s[1])
                if fr is None:
                    problems.append(f'{where}: fragment {s[1]} not found')
                else:
                    check(fr[1], fr[0], where, seen + (s[1],))

    n_ops = 0
    for f, ops, frags in parsed:
        rel = os.path.relpath(f, root)
        for kind, name, sel in ops:
            n_ops += 1
            check(sel, qroot if kind == 'query' else mroot, f'{rel} [{kind} {name}]')
        for name, (tname, sel) in frags.items():
            check(sel, tname, f'{rel} [fragment {name}]')
    return sorted(set(problems)), n_ops


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('endpoint', nargs='?', default=DEFAULT_ENDPOINT)
    ap.add_argument('--live-only', action='store_true',
                    help='check against the live schema alone, without the Hub Market App contract')
    ap.add_argument('--sdl', default=DEFAULT_SDL, help='the contract SDL to overlay (default: %(default)s)')
    ap.add_argument('--schema-file', metavar='PATH',
                    help='read the base schema from this SDL file (e.g. lib/core/graphql/schema.graphql) '
                         'instead of introspecting the endpoint; no network')
    args = ap.parse_args(argv)

    if args.schema_file:
        with open(args.schema_file, encoding='utf-8') as f:
            schema = schema_from_sdl(f.read())
        base, where = 'schema file', os.path.relpath(args.schema_file, ROOT)
    else:
        schema = fetch_schema(args.endpoint)
        base, where = 'live', args.endpoint
    types, qroot, mroot = index_schema(schema)
    if args.live_only:
        mode = f'{base} only ({where})'
    else:
        with open(args.sdl, encoding='utf-8') as f:
            merged = merge_sdl(types, parse_sdl(f.read()))
        mode = (f'{base} ({where}) + {os.path.relpath(args.sdl, ROOT)} '
                f'({len(merged["types"])} types, {len(merged["fields"])} fields overlaid)')
    parsed, fragments, parse_errors, n_files = collect(ROOT)
    problems, n_ops = validate(types, qroot, mroot, parsed, fragments)
    print(f'mode: {mode}')
    print(f'validated {n_ops} operations + {len(fragments)} fragments in {n_files} files')
    for p in parse_errors:
        print('  PARSE', p)
    for p in problems:
        print('  ✗', p)
    print(f'{len(problems)} problem(s)')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
