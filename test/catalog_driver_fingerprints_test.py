"""Synthetic future tags exercise shared proxies without editing upstream."""

import hashlib
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

script = Path(__file__).resolve().parent.parent / 'tool' / 'catalog_driver_fingerprints.py'
spec = importlib.util.spec_from_file_location('fingerprint_catalog', script)
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class FutureCatalogTest(unittest.TestCase):
    def test_shared_proxy_candidates_and_runtime_versions(self):
        with tempfile.TemporaryDirectory(prefix='dlssg-future-tags-') as temporary:
            repo = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(['git', '-C', str(repo), *arguments], stderr=subprocess.STDOUT)
            git('init', '-q')
            git('config', 'user.name', 'Fingerprint test')
            git('config', 'user.email', 'test@example.invalid')
            git('remote', 'add', 'origin', 'https://example.invalid/upstream')
            proxy = b'MZ-future-shared-proxy'
            (repo / 'version.dll').write_bytes(proxy)
            for version in ['0.4.0', '0.5.0', 'v1.0.0']:
                files = {
                    'dlssg_sm86/backend/sm86_backend.dll': f'backend {version}',
                    'dlssg_sm86/runtime/nvngx_dlssg.dll': f'runtime {version}',
                    "dlssg_sm86/models/model$special's.bin": f'resource {version}',
                }
                for name, text in files.items():
                    path = repo / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(text, encoding='utf-8')
                git('add', '.')
                git('commit', '-qm', version)
                git('tag', version)
            manifest = catalog.catalog(repo)
            digest = hashlib.sha256(proxy).hexdigest()
            self.assertEqual(manifest['tag_count'], 3)
            self.assertEqual(manifest['ambiguous_proxy_fingerprints'][digest], ['0.4.0', '0.5.0', '1.0.0'])
            self.assertEqual(manifest['proxy_fingerprint_count'], 1)
            self.assertNotEqual(manifest['runtime_fingerprints']['0.4.0']['dlssg_sm86/backend/sm86_backend.dll'], manifest['runtime_fingerprints']['0.5.0']['dlssg_sm86/backend/sm86_backend.dll'])
            self.assertIn("dlssg_sm86/models/model$special's.bin", manifest['runtime_fingerprints']['1.0.0'])

    def test_semantic_version_order_and_lfs_pointer_rejection(self):
        self.assertLess(catalog.version_key('0.9.0'), catalog.version_key('0.10.0'))
        self.assertLess(catalog.version_key('0.5.0-rc.2'), catalog.version_key('0.5.0-rc.10'))
        self.assertLess(catalog.version_key('0.5.0-rc.10'), catalog.version_key('0.5.0'))
        with tempfile.TemporaryDirectory(prefix='dlssg-lfs-tag-') as temporary:
            repo = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(['git', '-C', str(repo), *arguments], stderr=subprocess.STDOUT)
            git('init', '-q')
            git('config', 'user.name', 'Fingerprint test')
            git('config', 'user.email', 'test@example.invalid')
            git('remote', 'add', 'origin', 'https://example.invalid/upstream')
            (repo / 'version.dll').write_text('version https://git-lfs.github.com/spec/v1\n', encoding='utf-8')
            git('add', '.')
            git('commit', '-qm', 'pointer')
            git('tag', '0.5.0')
            with self.assertRaisesRegex(ValueError, 'not an actual PE DLL'):
                catalog.catalog(repo)


if __name__ == '__main__':
    unittest.main()
