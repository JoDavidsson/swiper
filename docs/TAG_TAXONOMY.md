# Swiper – Tag taxonomy

Normalized values used in Firestore and filters.

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
