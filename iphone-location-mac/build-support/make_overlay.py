"""Generate the local Swift module-map workaround without machine-specific paths."""
import json
from pathlib import Path
import sys

empty_map, output = map(Path, sys.argv[1:])
legacy = Path('/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap')
roots = []
if legacy.is_file():
    roots.append({'type': 'file', 'name': str(legacy),
                  'external-contents': str(empty_map.resolve())})
output.write_text(json.dumps({'version': 0, 'case-sensitive': 'false', 'roots': roots}), encoding='utf-8')
