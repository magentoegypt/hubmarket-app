#!/usr/bin/env python3
"""Fetch the live Magento GraphQL schema and write it as SDL for graphql_codegen.

Pure Python, no packages needed. Types are sorted by name so re-running only
diffs when the live schema changes.

Usage:
  python tool/introspect_to_sdl.py [endpoint] [out.graphql]
  defaults: https://hub-market.magento2.click/graphql -> lib/core/graphql/schema.graphql
"""
import json
import sys
import urllib.request

ENDPOINT = sys.argv[1] if len(sys.argv) > 1 else 'https://hub-market.magento2.click/graphql'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'lib/core/graphql/schema.graphql'

QUERY = """query IntrospectionQuery { __schema { queryType { name } mutationType { name } subscriptionType { name }
 types { ...FullType } directives { name description locations args { ...InputValue } } } }
fragment FullType on __Type { kind name description
 fields(includeDeprecated: true) { name description args { ...InputValue } type { ...TypeRef } isDeprecated deprecationReason }
 inputFields { ...InputValue } interfaces { ...TypeRef }
 enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason }
 possibleTypes { ...TypeRef } }
fragment InputValue on __InputValue { name description type { ...TypeRef } defaultValue }
fragment TypeRef on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name
 ofType { kind name ofType { kind name ofType { kind name } } } } } } } }"""

BUILTIN_SCALARS = {'String', 'Int', 'Float', 'Boolean', 'ID'}
BUILTIN_DIRECTIVES = {'skip', 'include', 'deprecated', 'specifiedBy', 'oneOf'}


def fetch():
    req = urllib.request.Request(ENDPOINT, data=json.dumps({'query': QUERY}).encode(),
                                 headers={'Content-Type': 'application/json',
                                          'User-Agent': 'HubMarketApp-introspect'})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = json.load(r)
    if 'errors' in body and not body.get('data'):
        raise SystemExit('introspection failed: ' + json.dumps(body['errors'])[:500])
    return body['data']['__schema']


def ref(t):
    if t['kind'] == 'NON_NULL':
        return ref(t['ofType']) + '!'
    if t['kind'] == 'LIST':
        return '[' + ref(t['ofType']) + ']'
    return t['name']


def desc(d, indent=''):
    if not d:
        return ''
    d = d.replace('"""', '\\"""')
    if '\n' in d or len(d) > 70:
        lines = '\n'.join(indent + l if l else l for l in d.split('\n'))
        return f'{indent}"""\n{lines}\n{indent}"""\n'
    return f'{indent}"""{d}"""\n'


def deprecated(x):
    if not x.get('isDeprecated'):
        return ''
    reason = x.get('deprecationReason')
    if reason is None or reason == 'No longer supported':
        return ' @deprecated'
    return ' @deprecated(reason: ' + json.dumps(reason, ensure_ascii=False) + ')'


def args(a_list, indent):
    if not a_list:
        return ''
    if not any(a.get('description') for a in a_list):
        return '(' + ', '.join(arg(a) for a in a_list) + ')'
    inner = ''.join(desc(a.get('description'), indent + '  ') + indent + '  ' + arg(a) + '\n' for a in a_list)
    return '(\n' + inner + indent + ')'


def arg(a):
    s = f"{a['name']}: {ref(a['type'])}"
    if a.get('defaultValue') is not None:
        s += f" = {a['defaultValue']}"
    return s


def print_type(t):
    k, name = t['kind'], t['name']
    out = desc(t.get('description'))
    if k == 'SCALAR':
        return out + f'scalar {name}\n'
    if k in ('OBJECT', 'INTERFACE'):
        impl = ''
        if t.get('interfaces'):
            impl = ' implements ' + ' & '.join(i['name'] for i in t['interfaces'])
        kw = 'type' if k == 'OBJECT' else 'interface'
        body = ''.join(desc(f.get('description'), '  ') + f"  {f['name']}{args(f.get('args'), '  ')}: {ref(f['type'])}{deprecated(f)}\n"
                       for f in t.get('fields') or [])
        return out + f'{kw} {name}{impl} {{\n{body}}}\n'
    if k == 'UNION':
        return out + f"union {name} = " + ' | '.join(p['name'] for p in t.get('possibleTypes') or []) + '\n'
    if k == 'ENUM':
        body = ''.join(desc(v.get('description'), '  ') + f"  {v['name']}{deprecated(v)}\n" for v in t.get('enumValues') or [])
        return out + f'enum {name} {{\n{body}}}\n'
    if k == 'INPUT_OBJECT':
        body = ''.join(desc(f.get('description'), '  ') + f"  {arg(f)}\n" for f in t.get('inputFields') or [])
        return out + f'input {name} {{\n{body}}}\n'
    raise ValueError(k)


def main():
    s = fetch()
    parts = []
    q, m = (s.get('queryType') or {}).get('name'), (s.get('mutationType') or {}).get('name')
    if (q and q != 'Query') or (m and m != 'Mutation'):
        parts.append('schema {\n' + (f'  query: {q}\n' if q else '') + (f'  mutation: {m}\n' if m else '') + '}\n')
    for d in sorted(s.get('directives') or [], key=lambda d: d['name']):
        if d['name'] in BUILTIN_DIRECTIVES:
            continue
        parts.append(desc(d.get('description')) + f"directive @{d['name']}{args(d.get('args'), '')} on " + ' | '.join(d['locations']) + '\n')
    for t in sorted(s['types'], key=lambda t: t['name']):
        if t['name'].startswith('__') or (t['kind'] == 'SCALAR' and t['name'] in BUILTIN_SCALARS):
            continue
        parts.append(print_type(t))
    sdl = '\n'.join(parts)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(sdl)
    print(f'Wrote {OUT} ({len(sdl)} bytes, {len(s["types"])} types) from {ENDPOINT}')


if __name__ == '__main__':
    main()
