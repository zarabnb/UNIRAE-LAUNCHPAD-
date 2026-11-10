from pathlib import Path
from html.parser import HTMLParser
import json, re
ROOT=Path(__file__).resolve().parents[1]
ui_path=ROOT/'frontend/UNIRAE-Premium-UI-v2.26.html'
ui=ui_path.read_text()
class Parser(HTMLParser): pass
Parser().feed(ui)
assert not re.search(r'airdrop', ui, re.I), 'Airdrop reference remains in primary UI'
assert 'class="brand-mini"' in ui and 'footer-brand' in ui
assert 'Launchpad at a glance' in ui and 'Explore launches' in ui
assert 'data-sort="watchlist"' in ui
assert 'class="timeframe active"' in ui and "querySelectorAll('.timeframe')" in ui
assert "querySelectorAll('.status-chip')" in ui
assert json.loads((ROOT/'backend/package.json').read_text())
assert json.loads((ROOT/'vercel/vercel.json').read_text())
print('V2.26 HTML structure, launchpad layout, no-airdrop UI, control interactions, and JSON checks passed')
