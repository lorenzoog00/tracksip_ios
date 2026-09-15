"""Static release guard; run from any directory with Python 3."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
project = (root / 'siptrack.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
assert 'Siptrack.storekit in Resources' not in project, 'Test purchases bundled'
assert 'FirebaseAppCheck in Frameworks' in project, 'App Check not linked'
assert '.superpowers/' in (root / '.gitignore').read_text(), 'Generated files are not ignored'
manifest = plistlib.loads((root / 'PrivacyInfo.xcprivacy').read_bytes())
assert any(x['NSPrivacyCollectedDataType'] == 'NSPrivacyCollectedDataTypeHealth'
           for x in manifest['NSPrivacyCollectedDataTypes'])
assert not (root / 'SipTrack/PrivacyInfo.xcprivacy').exists(), 'Duplicate manifest'
for file in (root / 'SipTrack').rglob('*.swift'):
    text = file.read_text(encoding='utf-8')
    assert not re.search(r'func (debugUnlockPro|debugDowngradeFree|generateTest\w+)', text), file
    assert 'Safe to drive around' not in text, file
assert 'store.isPro || userProfile.isPro' not in (root / 'SipTrack/State/AppState.swift').read_text(encoding='utf-8')
assert 'needs: checks' in (root / '.github/workflows/testflight.yml').read_text(encoding='utf-8')
print('Production source checks passed')
