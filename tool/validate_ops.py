#!/usr/bin/env python3
"""Validate every GraphQL operation in the app against the live Magento schema.

Finds operations in `.graphql` files and in Dart string literals (inline
`query`/`mutation`/`fragment` documents), then checks every selected field,
argument, inline-fragment type and fragment spread against the introspected
schema of the backend. Nothing is executed on the server — introspection only.

Usage:
  python tool/validate_ops.py [endpoint]      (default: Hub Market live GraphQL)
Exit code 1 when any operation references something the schema doesn't have.
"""
import json
import os
import re
import sys
import urllib.request

ENDPOINT = sys.argv[1] if len(sys.argv) > 1 else 'https://hub-market.magento2.click/graphql'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INTROSPECTION = """{ __schema { queryType { name } mutationType { name }
 types { kind name fields(includeDeprecated: true) { name args { name } type { ...R } }
 inputFields { name } possibleTypes { name } } } }
fragment R on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }"""


def load_schema():
    req = urllib.request.Request(ENDPOINT, data=json.dumps({'query': INTROSPECTION}).encode(),
                                 headers={'Content-Type': 'application/json', 'User-Agent': 'HubMarketApp-validate'})
    with urllib.request.urlopen(req, timeout=60) as r:
        s = json.load(r)['data']['__schema']
    types = {t['name']: t for t in s['types']}
    return types, s['queryType']['name'], (s.get('mutationType') or {}).get('name')


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


def main():
    types, qroot, mroot = load_schema()
    files = []
    for base in ('lib', 'test', 'integration_test'):
        for dp, dn, fn in os.walk(os.path.join(ROOT, base)):
            for f in fn:
                if f == 'schema.graphql' or f.endswith('.graphql.dart'):
                    continue
                if f.endswith('.graphql') or f.endswith('.dart'):
                    files.append(os.path.join(dp, f))
    parsed, fragments, parse_errors = [], {}, []
    for f in files:
        for doc in extract(f):
            try:
                ops, frags = P(tokenize(doc)).document()
            except SyntaxError as e:
                if re.search(r'\b(query|mutation)\s+\w+', doc):
                    parse_errors.append(f'{os.path.relpath(f, ROOT)}: {e}')
                continue
            fragments.update(frags)
            parsed.append((f, ops, frags))
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
        rel = os.path.relpath(f, ROOT)
        for kind, name, sel in ops:
            n_ops += 1
            root = qroot if kind == 'query' else mroot
            check(sel, root, f'{rel} [{kind} {name}]')
        for name, (tname, sel) in frags.items():
            check(sel, tname, f'{rel} [fragment {name}]')
    uniq = sorted(set(problems))
    print(f'validated {n_ops} operations + {len(fragments)} fragments in {len(files)} files against {ENDPOINT}')
    for p in parse_errors:
        print('  PARSE', p)
    for p in uniq:
        print('  ✗', p)
    print(f'{len(uniq)} problem(s)')
    sys.exit(1 if uniq else 0)


if __name__ == '__main__':
    main()
