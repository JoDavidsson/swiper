# Swiper – Tag taxonomy

Normalized values used in Firestore and filters.

## primaryCategory

- `sofa`, `armchair`, `dining_table`, `coffee_table`, `bed`, `chair`, `rug`, `lamp`, `storage`, `desk`, `decor`, `textile`, `unknown`

## sofaTypeShape

- `straight`, `corner`, `u_shaped`, `chaise`, `modular`
- Only set when `primaryCategory=sofa`

## sofaFunction

- `standard`, `sleeper`
- Only set when `primaryCategory=sofa`

## seatCountBucket

- `2`, `3`, `4_plus`
- Optional; only set when confidently extracted

## environment

- `indoor`, `outdoor`, `both`, `unknown`
- `unknown` is internal fallback and should not be displayed in customer UI

## sizeClass

- `small`: width &lt; 180 cm
- `medium`: 180–220 cm
- `large`: &gt; 220 cm

## material

- `fabric`, `leather`, `velvet`, `boucle`, `wood`, `metal`, `mixed`

## colorFamily

- `white`, `beige`, `brown`, `gray`, `black`, `green`, `blue`, `red`, `yellow`, `orange`, `pink`, `multi`

## newUsed

- `new`, `used`

## deliveryComplexity

- `low`, `medium`, `high`

## styleTags

Free-form strings from onboarding and feeds (e.g. Scandinavian, Modern, Vintage). Normalized to lowercase for matching.

## ecoTags

Array of strings (e.g. recycled, organic, FSC). Source-specific; no canonical enum in MVP.

## roomTypes

- `living_room`, `bedroom`, `outdoor`, `office`, `hallway`, `kids_room`
- Multi-valued placement tags (can coexist with `environment`)

## Deck Filter Keys (consumer-facing)

- `sizeClass`, `colorFamily`, `newUsed`
- `primaryCategory`
- `sofaTypeShape`, `sofaFunction`, `seatCountBucket`, `environment`
- `roomType`
- Legacy compatibility: `subCategory` is still accepted during migration.

## Legacy Compatibility Contract

- `predictedCategory` remains a legacy alias for `primaryCategory`.
- `subCategory` remains a derived legacy sofa descriptor for backward compatibility.
- New features should depend on the orthogonal axes instead of introducing new `subCategory` logic.

## Runtime Rule Adaptation

- Reviewer training outputs are stored in `categorizationTrainingConfig/latest`.
- Runtime behavior is controlled by `CATEGORIZATION_TRAINING_RULES_MODE`:
  - `off`: ignore learned rules
  - `shadow`: evaluate rules without changing decisions
  - `active`: apply validated rules to force reject when needed
