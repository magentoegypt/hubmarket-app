"""Tests for tool/firebase_config.sh: the Firebase client config is injected from a secret, checked to be
this app's, and never printed. Needs bash and python on PATH (CI has both); skipped where bash is missing."""
import base64
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'firebase_config.sh')
APP = 'com.hubmarket.app'
KEY = 'fake-api-key-that-must-never-be-printed'


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode('ascii')


def android_config(package=APP) -> bytes:
    return json.dumps({
        'project_info': {'project_id': 'hub-market-test'},
        'client': [{
            'client_info': {'android_client_info': {'package_name': package}},
            'api_key': [{'current_key': KEY}],
        }],
    }).encode('utf-8')


def ios_config(bundle=APP) -> bytes:
    return plistlib.dumps({'PROJECT_ID': 'hub-market-test', 'BUNDLE_ID': bundle, 'API_KEY': KEY})


@unittest.skipUnless(shutil.which('bash'), 'bash is needed')
class FirebaseConfigTest(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)

    def run_script(self, platform, **env):
        clean = {k: v for k, v in os.environ.items() if not k.startswith('FIREBASE_')}
        clean.update(env)
        return subprocess.run(
            ['bash', SCRIPT, platform], cwd=self.repo, env=clean,
            capture_output=True, text=True, timeout=60)

    def exists(self, relative):
        return os.path.exists(os.path.join(self.repo, relative))

    def test_no_secret_builds_without_fcm(self):
        for platform in ('android', 'ios'):
            result = self.run_script(platform)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('building without FCM', result.stdout)
        self.assertFalse(self.exists('android/app/google-services.json'))
        self.assertFalse(self.exists('ios/Runner/GoogleService-Info.plist'))

    def test_android_secret_is_written_and_never_printed(self):
        data = android_config()
        result = self.run_script('android', FIREBASE_ANDROID_CONFIG_BASE64=b64(data))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with open(os.path.join(self.repo, 'android/app/google-services.json'), 'rb') as f:
            self.assertEqual(f.read(), data)
        self.assertIn('hub-market-test', result.stdout)
        self.assertNotIn(KEY, result.stdout + result.stderr)

    def test_ios_secret_is_written_and_never_printed(self):
        data = ios_config()
        result = self.run_script('ios', FIREBASE_IOS_CONFIG_BASE64=b64(data))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with open(os.path.join(self.repo, 'ios/Runner/GoogleService-Info.plist'), 'rb') as f:
            self.assertEqual(f.read(), data)
        self.assertIn('hub-market-test', result.stdout)
        self.assertNotIn(KEY, result.stdout + result.stderr)

    def test_another_apps_config_is_refused(self):
        result = self.run_script(
            'android', FIREBASE_ANDROID_CONFIG_BASE64=b64(android_config('app.locafy.customer')))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('app.locafy.customer', result.stdout)
        self.assertFalse(self.exists('android/app/google-services.json'))

        result = self.run_script(
            'ios', FIREBASE_IOS_CONFIG_BASE64=b64(ios_config('magentoegypt.locafy')))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.exists('ios/Runner/GoogleService-Info.plist'))

    def test_a_bundle_id_override_is_honoured(self):
        result = self.run_script(
            'ios', FIREBASE_IOS_CONFIG_BASE64=b64(ios_config('com.hubmarket.app.dev')),
            FIREBASE_APP_ID='com.hubmarket.app.dev')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_garbage_is_refused(self):
        result = self.run_script('android', FIREBASE_ANDROID_CONFIG_BASE64='not base64 !!!')
        self.assertNotEqual(result.returncode, 0)
        result = self.run_script('android', FIREBASE_ANDROID_CONFIG_BASE64=b64(b'{"nope": 1}'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not parse', result.stdout)
        self.assertFalse(self.exists('android/app/google-services.json'))

    def test_unknown_platform_is_a_usage_error(self):
        self.assertEqual(self.run_script('web').returncode, 2)


if __name__ == '__main__':
    unittest.main()
