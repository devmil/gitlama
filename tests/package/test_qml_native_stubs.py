"""The QML tests' stand-ins for the native GitLamaNative types keep the
properties and signals of the C++ types they replace, so the QML they load
compiles against the same interface as in the application."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / 'rust-core/desktop/app/src/native'
STUBS = ROOT / 'qml/tests/stubs/GitLamaNative'


def registered_types():
    source = (NATIVE / 'graph_row.cpp').read_text(encoding='utf-8')
    return re.findall(r'qmlRegisterType<gitlama::(\w+)>\("GitLamaNative", 1, 0, "(\w+)"\)', source)


def native_interface(class_name):
    for header in NATIVE.glob('*.h'):
        text = header.read_text(encoding='utf-8')
        match = re.search(r'class ' + class_name + r'\b[^;{]*\{(.*?)\n\};', text, re.S)
        if match:
            body = match.group(1)
            properties = set(re.findall(r'Q_PROPERTY\(\s*[\w:<>\s*]+?\s\*?(\w+)\s+(?:READ|MEMBER)', body))
            signals = set()
            section = re.search(r'\nsignals:(.*?)(?:\n(?:public|private|protected)\b|\Z)', body, re.S)
            if section:
                signals = set(re.findall(r'void\s+(\w+)\s*\(', section.group(1)))
            return properties, signals
    raise AssertionError(f'no header declares {class_name}')


def stub_interface(qml_name):
    text = (STUBS / f'{qml_name}.qml').read_text(encoding='utf-8')
    properties = set(re.findall(r'^\s*(?:readonly\s+)?property\s+\w+\s+(\w+)', text, re.M))
    signals = set(re.findall(r'^\s*signal\s+(\w+)', text, re.M))
    return properties, signals


class QmlNativeStubsTest(unittest.TestCase):
    def test_every_registered_type_has_a_stub(self):
        types = registered_types()
        self.assertTrue(types)
        listed = (STUBS / 'qmldir').read_text(encoding='utf-8')
        for _, qml_name in types:
            self.assertIn(f'{qml_name} 1.0 {qml_name}.qml', listed)
            self.assertTrue((STUBS / f'{qml_name}.qml').is_file(), qml_name)

    def test_stubs_match_the_native_interface(self):
        for class_name, qml_name in registered_types():
            with self.subTest(qml_name):
                native_properties, native_signals = native_interface(class_name)
                stub_properties, stub_signals = stub_interface(qml_name)
                self.assertTrue(native_properties, class_name)
                self.assertEqual(stub_properties, native_properties)
                # QML declares a property's own change signal; the others must exist.
                missing = {name for name in native_signals if not name.endswith('Changed')} - stub_signals
                self.assertEqual(missing, set())


if __name__ == '__main__':
    unittest.main()
