# Marketing artwork

The feature graphic is vendored from the committed Devmil brand repository.
`manifest.json` pins that source separately from native icons. Edit the
composition in the brand repository's `scripts/build-feature-graphics.py`,
then vendor its committed SVG and update this manifest. The app's existing
brand generator renders website copies; `scripts/check_marketing_assets.py`
checks the pin without image dependencies. This change does not replace
published application packages or release assets.
