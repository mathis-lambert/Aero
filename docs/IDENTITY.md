# Visual identity exploration: dithered waves

Status: candidate direction, not implemented. The browser chrome stays neutral (see `DESIGN.md`); this direction is for brand surfaces.

## Direction

A smooth interference field of diagonal waves, rendered with ordered (Bayer) dithering into two tones: saturated blue (about `#2230F5`) or neutral gray, and white. The dot pattern evokes wind moving across a surface, which suits the name (Aero, air in motion) better than a literal illustration. It is monochrome and flat, so it works in light and dark appearances by swapping the two tones.

## Where it could appear

| Surface | Fit | Notes |
| --- | --- | --- |
| Website, launch material, onboarding (future) | Strong | Full-bleed, may animate |
| New Tab page | Possible | A faint static field behind the input; must not compete with the search field or reduce contrast |
| App icon | Adopted | A dithered Gilda Display capital A, the same serif as the wordmark (see `DESIGN.md`); the texture is fine enough to read as tone at 16–32 px |
| Chrome (sidebar, tab rows, settings) | No | Texture behind text hurts legibility; keep system surfaces |

## Implementation notes

- Render with a SwiftUI `ShaderLibrary` Metal `colorEffect`: a sum of two or three sine waves, thresholded against a 4×4 or 8×8 Bayer matrix at a fixed dot pitch in points (not pixels) so it stays crisp on Retina. No bitmap assets.
- A static field costs one render pass. Animation redraws every frame on the GPU, so it only runs briefly and on interaction (for example, on appearance of the New Tab page), never while idle, and not at all with Reduce Motion. With Reduce Transparency or Increase Contrast, drop the field.
- Keep text on a solid surface above the field, and check its contrast in both appearances.

## Open questions

Blue or gray as the default tone; whether the profile accent color can tint the field. The brand serif is Gilda Display, for the wordmark, the app icon and display titles; body text uses Instrument Sans, the app keeps SF Pro.
