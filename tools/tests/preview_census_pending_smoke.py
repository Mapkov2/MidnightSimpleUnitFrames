"""Supplemental scene findings must remain visible after historical zeroes."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scorecard

assert scorecard.preview_pending_sites({}) == 0
assert scorecard.preview_pending_sites({'j4_review': {'pending': [
    {'file': 'Preview/example.lua', 'sites': ['font', 'alpha'], 'reason': 'scene integration pending'}]}}) == 2
try:
    scorecard.preview_pending_sites({'j4_review': {'pending': [{'file': 'missing-sites'}]}})
except ValueError:
    pass
else:
    raise AssertionError('invalid pending preview findings passed')
print('preview census: supplemental pending sites remain counted and fail the zero target')
