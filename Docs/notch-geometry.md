# Notch geometry sources

Reviewed 2026-10-29.

## Measured display bounds

The built-in display connected during this session reported a 1512 × 982-point frame, 2× backing scale, and a 32-point top safe inset. The auxiliary left area ended at x=663; the right area began at x=848. The camera region therefore spanned **185 × 32 points** in that display mode. These are the public API's bounding regions, not a physical corner mask. The app reads these values per screen instead of hardcoding this machine's dimensions.

- Apple: [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)
- Apple: [NSScreen.auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
- Apple: [NSScreen.auxiliaryTopRightArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n)

## Public curve reference

[boring.notch's NotchShape.swift](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/NotchShape.swift) defines independently adjustable upper and lower curves with defaults of 6 and 14 points, respectively. It credits DynamicNotchKit as its original source. We use these numeric defaults as a visual reference; our path and rendering implementation are independent.

These are application shape parameters. They are **not a certified hardware specification** and do not establish an exact physical fit for every MacBook. Apple's public screen APIs provide rectangular safe areas, not the housing's corner contour. The Apple API and design resources reviewed did not provide a per-model physical notch curve for this MacBook.

## Default side indicators

The default layout draws three dots vertically beside the left edge and a battery rail beside the right edge. No bottom or top path is drawn or clickable. The path center is offset by half its thickness so the inner edge meets the measured camera-region boundary; no extra 0.5-point gap is added. Dot/rail endpoints stay near the straight side between the reference upper and lower curves. Thickness defaults to 3 points (six backing pixels at 2×), with user adjustments preserved. Full Contour remains optional and explicitly approximate.

## Verification limits

The built-in display was detected and the previous contour enabled during this session. Physical fit was reported imperfect by the user; it was not independently measured to pixel accuracy. The display was then closed, so the revised side-only layout has not been visually verified against its physical camera housing. The current app reported Accessibility as unavailable despite a similarly named enabled entry in System Settings; successful native menu activation remains unverified. Ad-hoc rebuilds can require renewed authorization of the current app. We do not change TCC settings or weaken code-signing requirements to bypass that authorization.
