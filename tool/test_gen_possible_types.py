"""Tests for tool/gen_possible_types.py."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gen_possible_types as gen  # noqa: E402


class PossibleTypesTest(unittest.TestCase):
    def test_committed_file_is_up_to_date(self):
        self.assertEqual(gen.main(['--check']), 0)

    def test_implementers_interface_inheritance_and_unions(self):
        sdl = '''
"""An interface with "quotes" and implements in its description."""
interface Node { id: ID! }
interface Product implements Node { sku: String }
# type Ghost implements Product { sku: String }
type Simple implements Product & Node { sku: String id: ID! }
type Bundle implements Product { sku: String id: ID! }
type Other { x: Int }
union SearchHit = Simple | Other

union Anything =
  | Product
  | Other
'''
        mapping = gen.possible_types([sdl])
        self.assertEqual(mapping['Product'], {'Simple', 'Bundle'})
        self.assertEqual(mapping['Node'], {'Simple', 'Bundle'})
        self.assertEqual(mapping['SearchHit'], {'Simple', 'Other'})
        self.assertEqual(mapping['Anything'], {'Simple', 'Bundle', 'Other'})
        self.assertNotIn('Ghost', mapping['Product'])

    def test_magento_style_redeclaration_adds_no_implementers(self):
        live = 'interface ProductInterface { sku: String }\n' \
               'type SimpleProduct implements ProductInterface { sku: String }\n'
        contract = 'interface ProductInterface { hm_seller: String }\n'
        mapping = gen.possible_types([live, contract])
        self.assertEqual(mapping['ProductInterface'], {'SimpleProduct'})


if __name__ == '__main__':
    unittest.main()
