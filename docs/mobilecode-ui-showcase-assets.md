# MobileCode UI Showcase Assets

This file records the curated visual assets used by the README and GitHub Pages product site.

## Source

- Reference pack: `reference_ui/local_dialog_all_images_svgs_final_pack/`
- Public site path: `app/public/showcase/`
- Pages usage: `app/src/pages/Home.tsx`
- README usage: `README.md`

## Selection Rules

- Keep assets that clearly match the MobileCode / CodeLoong product direction.
- Exclude reading-themed assets, Just-Agent assets, unrelated roles, duplicates, and low-fit experiments.
- Prefer lightweight brand SVGs for logo/icon use.
- Use PNG previews for large role-state artwork instead of publishing the multi-megabyte raw state SVGs on the landing page.
- Treat these as brand and promotional design references, not runtime APK screenshots.

## Public Asset Index

| Public asset | Source asset | Current use |
|---|---|---|
| `app/public/showcase/mobilecode-icon-v2.svg` | `local_files/svg/mobilecode_brand_svg_v2/mobilecode-icon-v2.svg` | README hero icon, Pages design wall |
| `app/public/showcase/mobilecode-logo-v2.svg` | `local_files/svg/mobilecode_brand_svg_v2/mobilecode-logo-v2.svg` | Pages design wall |
| `app/public/showcase/mobilecode-mascot-v2.svg` | `local_files/svg/mobilecode_brand_svg_v2/mobilecode-mascot-v2.svg` | Pages design wall |
| `app/public/showcase/mobilecode-logo-v2-mobile-vibe.svg` | `local_files/svg/mobilecode_brand_svg_v2/mobilecode-logo-v2-mobile-vibe.svg` | Pages design wall |
| `app/public/showcase/mobilecode-code-with-your-buddy.png` | `local_files/images/mobilecode_code_with_your_buddy.png` | README preview, Pages lead visual |
| `app/public/showcase/mobilecode-brand-identity-sheet.png` | `local_files/images/mobilecode_brand_identity_sheet.png` | README preview, Pages lead visual |
| `app/public/showcase/mobilecode-mascot-wordmark.png` | `local_files/images/tech_mascot_with_smartphone_and_logo.png` | README preview, Pages design wall |
| `app/public/showcase/mobilecode-logo-v2.png` | `from_zips/mobilecode-brand-svg-v2-pack/images/mobilecode_brand_svg_v2/mobilecode-logo-v2.png` | Raster fallback / future social preview |
| `app/public/showcase/mobilecode-icon-v2.png` | `from_zips/mobilecode-brand-svg-v2-pack/images/mobilecode_brand_svg_v2/mobilecode-icon-v2.png` | Raster fallback / future social preview |
| `app/public/showcase/mobilecode-logo-v2-mobile-vibe.png` | `from_zips/mobilecode-brand-svg-v2-pack/images/mobilecode_brand_svg_v2/mobilecode-logo-v2-mobile-vibe.png` | Raster fallback / future social preview |
| `app/public/showcase/codeloong-state-coding-heat.png` | `from_zips/codeloong_svg_state_pack/images/codeloong_svg_states/png_preview/codeloong_coding_heat_dynamic.png` | Pages design wall |
| `app/public/showcase/codeloong-state-thinking.png` | `from_zips/codeloong_svg_state_pack/images/codeloong_svg_states/png_preview/codeloong_thinking_static.png` | Pages design wall |
| `app/public/showcase/codeloong-state-loading.png` | `from_zips/codeloong_svg_state_pack/images/codeloong_svg_states/png_preview/codeloong_loading_dynamic.png` | Pages design wall |

## Deferred

- Runtime APK screenshots should be captured after the mobile app is verified in a real Android QA flow.
- Large animated/state SVGs can be optimized later before direct public use.
- The README should stay limited to a few strong visuals so the first viewport remains readable on GitHub.
