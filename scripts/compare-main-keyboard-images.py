#!/usr/bin/env python3
"""Compare captured native/Shika keycap geometry (402 pt, 3x), not the candidate bar."""
import json
from collections import deque
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parent.parent
folder = root / 'docs/validation/ios26-implementation'
native = Image.open(root / 'docs/validation/ios26-reference/chinese-light.png').convert('RGB').crop((0, 1755, 1206, 2403))
actual = Image.open(folder / 'chinese-402-light.png').convert('RGB')

def components(image):
    width, height = image.size
    mask = bytearray(1 if min(pixel) >= 250 else 0 for pixel in image.getdata())
    boxes = []
    for start in range(len(mask)):
        if not mask[start]:
            continue
        mask[start] = 0
        queue = deque([start]); count = 0
        left = right = start % width; top = bottom = start // width
        while queue:
            position = queue.popleft(); x, y = position % width, position // width
            count += 1; left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            neighbors = []
            if x: neighbors.append(position - 1)
            if x + 1 < width: neighbors.append(position + 1)
            if y: neighbors.append(position - width)
            if y + 1 < height: neighbors.append(position + width)
            for neighbor in neighbors:
                if mask[neighbor]: mask[neighbor] = 0; queue.append(neighbor)
        if count > 5000: boxes.append([left, top, right, bottom])
    return sorted(boxes, key=lambda b: (round(b[1] / 100), b[0]))

reference, result = components(native), components(actual)
assert len(reference) == len(result) == 32, (len(reference), len(result))
differences = [[b - a for a, b in zip(old, new)] for old, new in zip(reference, result)]
max_error = max(abs(value) for delta in differences for value in delta)
report = {'reference': 'native iOS 26.5 / iPhone 17 Pro / Chinese Pinyin', 'comparison': '32 visible keycap bounds, native crop y1755..2403, inclusive pixels', 'nativeBounds': reference, 'shikaBounds': result, 'edgeDifferencesPixels': differences, 'maxAbsoluteEdgeErrorPixels': max_error, 'tolerancePixels': 1, 'passed': max_error <= 1, 'scope': 'keycap geometry only; glyphs, blur, animations and customized labels excluded'}
folder.mkdir(exist_ok=True)
(folder / 'geometry-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
comparison = Image.new('RGB', (1206, 1296)); comparison.paste(native, (0, 0)); comparison.paste(actual, (0, 648))
comparison.save(folder / 'native-vs-shika.png')
print(json.dumps({'keys': len(result), 'maxEdgeErrorPixels': max_error, 'passed': report['passed']}))
raise SystemExit(0 if report['passed'] else 1)
