"""Moved preview adapters stay inside the source-bound census."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scorecard
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / 'tools').mkdir()
    menu = root / scorecard.schema_coverage.MENU
    rows = []
    for name in scorecard.PREVIEW_FILES:
        p = menu / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('return true\n', encoding='utf-8')
        rows.append({'file':name, 'source_sha256':hashlib.sha256(p.read_text().encode()).hexdigest(),
            'runtime_owner':'shared scene', 'reviewed_ranges':[[1,1]], 'baseline_line_count':1,
            'before_physical':1, 'before_code':1, 'remaining_physical':0, 'remaining_code':0})
    support = menu / 'Pages/MovedAdapter.lua'
    support.write_text('return true\n', encoding='utf-8')
    rows[0]['support_sources'] = [{'file':'Pages/MovedAdapter.lua', 'source_sha256':hashlib.sha256(support.read_text().encode()).hexdigest()}]
    count = len(rows)
    evidence = {'version':1, 'files':rows, 'before_physical':count, 'before_code':count,
                'remaining_physical':0, 'remaining_code':0}
    (root / 'tools/preview_render_census.json').write_text(json.dumps(evidence), encoding='utf-8')
    scorecard.preview_render_census(root)
    support.write_text('return false\n', encoding='utf-8')
    try:
        scorecard.preview_render_census(root)
    except ValueError:
        pass
    else:
        raise AssertionError('stale moved preview adapter escaped the census')
print('PASS census rejects stale moved preview adapters')
