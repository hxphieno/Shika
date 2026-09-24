# iOS 26.5 native reference capture

Captured 2026-09-25 on iPhone 17 Pro simulator, iOS 26.5, 402 × 874 points / 1206 × 2622 pixels (3×), in the Shika TextEditor. These are unmodified native-system screenshots, not app renders.

Files: `chinese-light.png`, `chinese-dark.png`, `japanese-light.png`, `japanese-dark.png`.

The Chinese reference is Simplified Chinese Pinyin, full QWERTY. The Japanese reference is Japanese Romaji. Candidate areas differ and are outside the redesign scope.

## Measured key geometry (portrait)

Pixel rectangles are inclusive visible white keycap bounds, measured away from antialiased corners.

| Feature | Native pixels | Points |
|---|---|---|
| Q cap | x 20…119, y 1773…1901 | x≈6.67, width≈33.33, height 43 |
| W cap | x 138…238 | width≈33.67 |
| Horizontal gap | 18 pixels between adjacent cap bounds | 6 |
| Row pitch | 162 | 54 |
| Vertical gap | 33 | 11 |
| Chinese row 2 start | x 79, 9 keys | x≈26.33 |
| Japanese row 2 | 10 keys, ends in ー | same first-row grid |
| Third-row Shift | x 20…155 | width≈45.33 |
| Third-row delete | x 1050…1186 | width≈45.67 |
| Third-row Z | x 197…297 | x≈65.67 |
| Chinese 123 | x 20…149 | width≈43.33 |
| Chinese emoji | x 168…297 | width≈43.33 |
| Japanese 123 | x 20…297 | width≈92.67 |
| Space | x 316…889 | width≈191.33 |
| Return | x 908…1186 | width 93 |
| Final-row y | 2259…2387 | 43 high |

Antialiased edges imply fractional point coordinates. Estimated keycap corner radius: 8 pt. Q dark-glyph bounding box is x54…86/y1818…1869 (11 × 17.33 pt); W x163…212/y1819…1856 (16.67 × 12.67 pt). An initial visual estimate was 26 pt; direct comparison with the rendered Shika font showed it was too large. Iterative raster comparison then calibrated the implementation to 25 pt with CoreText glyph-ink optical centering; size alone was insufficient because the advance-width center differed from the visible glyph center. Font identification remains an inference from raster comparison rather than a reported private system value.

Light mode interior keycap RGB 255,255,255; bottom keyboard background RGB 223,224,230. Dark mode main keycap interior RGB 61,61,61; lower background RGB 23,23,23. The system background is translucent and varies by vertical position and host content, so these colors are samples rather than universal constants.

All original enabled keyboards and their ordering were restored after capture: Chinese full QWERTY, emoji, English US, Chinese nine-key, Chinese handwriting, Japanese Kana, Japanese Romaji, English Japan, Shika. Appearance restored to light.

## Real pressed-state capture

`japanese-pressed-q.png`, `japanese-pressed-p.png`, and `japanese-pressed-t.png` are original frames extracted from an iOS Simulator H.264 screen recording while actual CUA coordinate clicks pressed those keys. They are genuine native pressed states, not reconstructed mockups. H.264 causes small color and edge compression errors; use static PNG screenshots for exact resting colors. AX button activation was insufficient for capturing touch-down feedback, so coordinate input was used.

Measured bubble bounds: left q cap x≈20…185, right p cap x≈1026…1186, central t cap x≈458…629 pixels. Edge bubbles align to the outer keycap edge, with the neck bending inward. Top is approximately y1575 and bottom y1902, giving about 109–110 pt total height. Top-row normal key starts y1773, so the enlarged cap extends roughly 66 pt above it. Central cap shoulder begins around y1730 and narrows back toward the key by y1775. Enlarged t glyph x530…558/y1643…1715 and q x74…123/y1657…1734 support about 36 pt text with glyph tops 23–27 pt below the bubble top.

The Japanese footer adapts to enabled keyboards: when only Japanese Romaji and emoji were enabled during the first static capture, 123 occupied both left slots. After restoring multiple input languages, the native Japanese footer uses four slots (123, emoji, space, return), matching the Chinese reference. Shika retains its requested deer control in the second slot.
