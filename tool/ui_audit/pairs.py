"""Build the Figma-vs-app comparison images for every screen that has an app render.

    python tool/ui_audit/pairs.py [LOCALE] [NAME_FILTER]

Figma frames live in build/ui_audit/figma/<name>.png for English and build/ui_audit/figma_ar/<name>.png for
Arabic (downloaded from the file, see docs/ui-audit.md; the names are the PAIRS keys), the app's renders in
build/test_screens/<capture>_<locale>.png (written by the widget tests through captureScreen). PAIRS says
which capture shows which frame; a frame can have several (states). Writes
build/ui_audit/cmp/<name>[__<capture>].png (English) or build/ui_audit/cmp_ar/... (Arabic), Figma left, app
right, and lists the frames that still have no render.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIGMA_DIRS = {'en': ROOT / 'build' / 'ui_audit' / 'figma', 'ar': ROOT / 'build' / 'ui_audit' / 'figma_ar'}
SHOTS = ROOT / 'build' / 'test_screens'
CMP_DIRS = {'en': ROOT / 'build' / 'ui_audit' / 'cmp', 'ar': ROOT / 'build' / 'ui_audit' / 'cmp_ar'}

# Figma frame name -> app captures (without the _<locale>.png suffix).
PAIRS = {
    'A01_splash': ['audit_01_splash'],
    'A02_welcome': ['welcome_logo_panel', 'welcome_slides'],
    'A03_sign_in': ['03_sign_in'],
    'A04_register': ['04_register'],
    'A05_verify': ['05_verify_code'],
    'A06_forgot': ['06_forgot_password'],
    'B07_home': ['home_hubapp', 'home'],
    'B08_categories': ['audit_08_categories'],
    'B09_search': ['search_09_typeahead'],
    'B09b_search_landing': ['audit_09b_search_landing'],
    'B09c_search_results': ['search_09c_results'],
    'B10_plp': ['audit_10_plp'],
    'B10b_deals': ['deals'],
    'B10c_bundles': ['bundles'],
    'B10d_brands': ['brands'],
    'B10e_brand_page': ['brand_page'],
    'B11_filters': ['audit_11_filters', 'audit_11_sort', 'deals_filters'],
    'C12_stores': ['stores_12_list_p31'],
    'C13_store': ['stores_13_store_p31'],
    'C13b_store_about': ['stores_13b_about_p31'],
    'C14_pdp': ['p3_14_sold_by', 'pdp_other_sellers'],
    'C14b_bundle_pdp': ['p3_14b_bundle'],
    'C14c_added_to_cart': ['added_to_cart'],
    'C15_reviews': ['15_reviews'],
    'C15b_write_review': ['audit_15b_write_review'],
    'D16_cart': ['p3_16_cart'],
    'D17_checkout_ship': ['checkout_17_shipping'],
    'D17a_checkout_guest': ['checkout_17a_guest'],
    'D18_checkout_pay': ['checkout_18_payment'],
    'D18b_checkout_review': ['checkout_18b_review'],
    'D19_order_placed': ['checkout_19_order_placed'],
    'E20_account': ['audit_20_account'],
    'E20b_privacy': ['20b_privacy_data'],
    'E20c_profile': ['audit_20c_profile'],
    'E20d_credit': ['20d_my_credit'],
    'E20e_payment_methods': ['audit_20e_payment_methods'],
    'E20f_my_reviews': ['20f_my_reviews'],
    'E20g_notifications': ['audit_20g_notifications'],
    'E20h_notif_settings': ['20h_notification_settings'],
    'E21_orders': ['audit_21_orders'],
    'E21b_cancel_order': ['audit_21b_cancel_order'],
    'E22_order_detail': ['audit_22_order_detail', 'p3_22_order'],
    'E23_return_request': ['audit_23_request_return'],
    'E23b_my_returns': ['audit_23b_my_returns'],
    'E23c_return_detail': ['audit_23c_return_detail'],
    'E24_addresses': ['audit_24_addresses'],
    'E24b_address_form': ['audit_24b_address_form'],
    'E25_wishlist': ['audit_25_wishlist'],
    'E26_track_order': ['audit_26_track_order', 'p31_26_packages'],
    'E27_help': ['27_help_centre'],
    'E28_cms_page': ['28_content_page'],
    'F_S1_empty_cart': ['audit_S1_empty_cart'],
    'F_S2_no_results': ['search_S2_no_results'],
    'F_S3_offline': ['S3_offline'],
    'F_S4_loading': ['S4_home_loading', 'cart_loading', 'orders_loading'],
    'F_S5_payment_failed': ['audit_S5_payment_failed'],
    'F_S6_signin_errors': ['S6_sign_in_errors'],
    'F_S7_not_found': ['audit_S7_not_found'],
}


def main(argv: list[str]) -> int:
    locale = argv[1] if len(argv) > 1 else 'en'
    only = argv[2] if len(argv) > 2 else ''
    FIGMA = FIGMA_DIRS.get(locale, FIGMA_DIRS['en'])
    CMP = CMP_DIRS.get(locale, CMP_DIRS['en'])
    missing = []
    for name, captures in PAIRS.items():
        if only and only not in name:
            continue
        figma = FIGMA / f'{name}.png'
        if not figma.exists():
            print(f'!! no Figma image for {name}')
            continue
        made = 0
        for capture in captures:
            shot = SHOTS / f'{capture}_{locale}.png'
            if not shot.exists():
                continue
            out = CMP / (f'{name}.png' if made == 0 else f'{name}__{capture}.png')
            subprocess.run([sys.executable, str(ROOT / 'tool' / 'ui_audit' / 'compose.py'),
                            str(figma), str(shot), str(out)], check=True, stdout=subprocess.DEVNULL)
            made += 1
        if not made:
            missing.append(name)
    print('composed; frames without an app render (%d): %s' % (len(missing), ', '.join(missing) or 'none'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
