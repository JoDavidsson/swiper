# Swiper – Frontend Guidelines

> **Last updated:** 2026-02-05  
> Complete design system and component patterns for Flutter development.

---

## 1. Design Principles

1. **Mobile-first** – Design for phone screens, adapt for web/tablet
2. **Gesture-driven** – Swipe as primary interaction, taps secondary
3. **Instant feedback** – Every interaction has visual response
4. **Minimal chrome** – Content takes center stage
5. **Accessibility** – WCAG 2.1 AA compliant
6. **Premium imagery** – Never distort; always show full product

---

## 2. Color Palette

### Brand Colors

| Name | Hex | Usage |
|------|-----|-------|
| **Primary** | `#6366F1` | CTAs, active states, links |
| **Primary Variant** | `#4F46E5` | Pressed states, emphasis |
| **Secondary** | `#10B981` | Success, confirmation |
| **Error** | `#EF4444` | Errors, destructive actions |
| **Warning** | `#F59E0B` | Warnings, caution |

### Neutrals (Light Mode)

| Name | Hex | Usage |
|------|-----|-------|
| **Background** | `#FFFFFF` | Page background |
| **Surface** | `#F9FAFB` | Cards, elevated surfaces |
| **Surface Variant** | `#F3F4F6` | Dividers, subtle backgrounds |
| **On Surface** | `#111827` | Primary text |
| **On Surface Variant** | `#6B7280` | Secondary text |
| **Outline** | `#E5E7EB` | Borders, dividers |

### Neutrals (Dark Mode)

| Name | Hex | Usage |
|------|-----|-------|
| **Background** | `#111827` | Page background |
| **Surface** | `#1F2937` | Cards, elevated surfaces |
| **Surface Variant** | `#374151` | Dividers, subtle backgrounds |
| **On Surface** | `#F9FAFB` | Primary text |
| **On Surface Variant** | `#9CA3AF` | Secondary text |
| **Outline** | `#374151` | Borders, dividers |

### Semantic Colors

| State | Hex | Usage |
|-------|-----|-------|
| **Like** | `#10B981` | Like swipe, saved items |
| **Dislike** | `#EF4444` | Dislike swipe |
| **Neutral** | `#6B7280` | Skip, undo |
| **Featured** | `#F59E0B` | Featured badge |

### Confidence Score Colors

| Band | Background | Text |
|------|------------|------|
| **Green** | `#10B981` | `#FFFFFF` |
| **Yellow** | `#F59E0B` | `#111827` |
| **Red** | `#EF4444` | `#FFFFFF` |

---

## 3. Typography

### Font Stack

```dart
// Primary font
fontFamily: 'Inter'

// Fallback (system)
fontFamilyFallback: ['.SF Pro Text', 'Roboto', 'sans-serif']
```

### Type Scale

| Style | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| **Display Large** | 57px | 400 | 1.12 | Hero text (rare) |
| **Display Medium** | 45px | 400 | 1.16 | — |
| **Display Small** | 36px | 400 | 1.22 | — |
| **Headline Large** | 32px | 400 | 1.25 | Page titles |
| **Headline Medium** | 28px | 400 | 1.29 | Section headers |
| **Headline Small** | 24px | 400 | 1.33 | Card titles |
| **Title Large** | 22px | 500 | 1.27 | List headers |
| **Title Medium** | 16px | 500 | 1.50 | Subheaders |
| **Title Small** | 14px | 500 | 1.43 | Captions with emphasis |
| **Body Large** | 16px | 400 | 1.50 | Primary body text |
| **Body Medium** | 14px | 400 | 1.43 | Secondary body text |
| **Body Small** | 12px | 400 | 1.33 | Tertiary text |
| **Label Large** | 14px | 500 | 1.43 | Buttons |
| **Label Medium** | 12px | 500 | 1.33 | Chips, badges |
| **Label Small** | 11px | 500 | 1.45 | Fine print |

### Flutter Theme Integration

```dart
// lib/core/theme.dart
ThemeData(
  textTheme: TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w400,
      height: 1.25,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.43,
    ),
  ),
)
```

---

## 4. Spacing Scale

Use consistent spacing multiples of 4px.

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4px | Tight inline spacing |
| `sm` | 8px | Icon padding, compact lists |
| `md` | 16px | Standard padding, gaps |
| `lg` | 24px | Section spacing |
| `xl` | 32px | Large gaps |
| `xxl` | 48px | Page margins (desktop) |

### Flutter Constants

```dart
// lib/core/spacing.dart
abstract class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}
```

---

## 5. Responsive Breakpoints

| Breakpoint | Width | Layout |
|------------|-------|--------|
| **Mobile** | < 600px | Single column, full-width cards |
| **Tablet** | 600–1024px | Side margins, larger cards |
| **Desktop** | > 1024px | Centered content, max-width 600px |

### Implementation

```dart
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 600) {
      return MobileLayout();
    } else if (constraints.maxWidth < 1024) {
      return TabletLayout();
    } else {
      return DesktopLayout();
    }
  },
)
```

### Swipe Deck Sizing

| Platform | Card Width | Card Height |
|----------|------------|-------------|
| Mobile | 100% - 32px | 70% viewport |
| Tablet | 400px | 500px |
| Desktop | 400px | 500px |

---

## 6. Premium Image Display Specification

### Goals

- **Never stretch/distort** furniture images
- **Avoid ugly letterboxing** (black bars)
- Make every card look **premium and consistent**
- Support wide/landscape product images on mobile portrait cards

### Recommended Pattern: Contain + Blurred Background

Card uses two layers:

1. **Background layer**: Same image, scaled to cover, blurred
2. **Foreground layer**: Same image, scaled to contain (shows full product)

### Flutter Implementation

```dart
// lib/shared/widgets/premium_image_card.dart

class PremiumImageCard extends StatelessWidget {
  final String imageUrl;
  final double aspectRatio;
  
  const PremiumImageCard({
    required this.imageUrl,
    this.aspectRatio = 4 / 5,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background: blurred, covers entire card
            Transform.scale(
              scale: 1.1, // Slight overscale to avoid edges
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Foreground: full product, centered
            Center(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### CSS Equivalent (for web reference)

```css
.card {
  position: relative;
  aspect-ratio: 4 / 5;
  overflow: hidden;
  border-radius: 16px;
}

.card-bg {
  position: absolute;
  inset: 0;
  background-image: url(...);
  background-size: cover;
  background-position: center;
  filter: blur(18px);
  transform: scale(1.1);
}

.card-fg {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
}

.card-fg img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}
```

### Image Sizes and CDN

Request appropriate image size based on display:

| Context | Request Size |
|---------|-------------|
| Card thumbnail | 400w |
| Card main | 800w |
| Detail sheet | 1200w |
| Gallery zoom | Original |

```dart
String getImageUrl(String baseUrl, int width) {
  // CDN resizing pattern
  return '$baseUrl?w=$width&format=webp';
}
```

### Fallback Strategy

If WebP not supported:
```dart
CachedNetworkImage(
  imageUrl: getImageUrl(url, 800),
  placeholder: (_, __) => ShimmerPlaceholder(),
  errorWidget: (_, __, ___) => Image.network(
    url, // Fallback to original
    fit: BoxFit.contain,
  ),
)
```

---

## 7. Component Patterns

### Swipe Card (with Premium Image)

```dart
// Structure
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 20,
        offset: Offset(0, 10),
      ),
    ],
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              PremiumImageCard(imageUrl: imageUrl),
              if (isFeatured) FeaturedBadge(),
            ],
          ),
        ),
        ProductInfoBar(),
      ],
    ),
  ),
)

// Card states
// - Default: No transform
// - Dragging: Rotation based on dx (-15° to 15°)
// - Like hint: Green overlay, heart icon
// - Dislike hint: Red overlay, X icon
// - Animating out: Scale down + slide + rotate
```

### Featured Badge

```dart
Positioned(
  top: 12,
  left: 12,
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Color(0xFFF59E0B), // Warning/Featured color
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      'Featured',
      style: TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
)
```

### Confidence Score Badge

```dart
Widget buildScoreBadge(double score, String band) {
  final color = switch (band) {
    'green' => Color(0xFF10B981),
    'yellow' => Color(0xFFF59E0B),
    'red' => Color(0xFFEF4444),
    _ => Colors.grey,
  };
  
  final textColor = band == 'yellow' ? Colors.black : Colors.white;
  
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '${score.toStringAsFixed(1)}',
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
```

### Buttons

| Type | Usage | Style |
|------|-------|-------|
| **Primary** | Main CTA | Filled, primary color |
| **Secondary** | Alternative action | Outlined, primary color |
| **Tertiary** | Low emphasis | Text only |
| **Icon** | Compact action | Circular, subtle bg |
| **FAB** | Primary floating action | Large, elevated |

```dart
// Primary button
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Colors.white,
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  child: Text('Action'),
)
```

### Bottom Action Bar

```dart
// Swipe screen bottom bar
Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    // Dislike
    IconButton(
      icon: Icon(Icons.close, size: 32),
      color: Colors.red,
      onPressed: onDislike,
    ),
    // Undo (optional)
    IconButton(
      icon: Icon(Icons.undo, size: 24),
      color: Colors.grey,
      onPressed: onUndo,
    ),
    // Like
    IconButton(
      icon: Icon(Icons.favorite, size: 32),
      color: Colors.green,
      onPressed: onLike,
    ),
  ],
)
```

### Product Info Bar

```dart
Container(
  padding: EdgeInsets.all(16),
  color: Colors.white,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        productTitle,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      SizedBox(height: 4),
      Text(
        formatPrice(priceSek),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      SizedBox(height: 4),
      Text(
        retailer,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  ),
)
```

### Insight Feed Card (Retailer Console)

```dart
Card(
  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(insightIcon, color: insightColor),
            SizedBox(width: 8),
            Text(
              insightType.toUpperCase(),
              style: TextStyle(
                color: insightColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 16),
        ElevatedButton(
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ],
    ),
  ),
)
```

### List Tiles (Likes/Shortlist)

```dart
ListTile(
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  leading: ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: CachedNetworkImage(
      imageUrl: thumbnailUrl,
      width: 64,
      height: 64,
      fit: BoxFit.cover,
    ),
  ),
  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
  subtitle: Text(formatPrice(price)),
  trailing: IconButton(
    icon: Icon(Icons.open_in_new),
    onPressed: onTapOutbound,
  ),
)
```

---

## 8. Animation Guidelines

### Durations

| Type | Duration | Curve |
|------|----------|-------|
| **Micro** | 100ms | `easeOut` |
| **Short** | 200ms | `easeInOut` |
| **Medium** | 300ms | `easeInOut` |
| **Long** | 500ms | `easeInOut` |

### Swipe Animations

| Action | Animation |
|--------|-----------|
| **Drag** | Real-time transform (rotation, translation) |
| **Release (swipe)** | 200ms slide out + fade |
| **Release (snap back)** | 200ms spring to origin |
| **Undo** | 300ms reverse slide + fade in |
| **New card enter** | 200ms scale up from 0.95 + fade in |

### Transitions

| Navigation | Transition |
|------------|------------|
| **Push** | Slide from right |
| **Pop** | Slide to right |
| **Modal** | Slide from bottom |
| **Tab switch** | Fade cross-dissolve |

---

## 9. Icons

### Icon Set

Use Material Icons (`Icons.*`) as primary set.

### Sizes

| Size | Value | Usage |
|------|-------|-------|
| **Small** | 18px | Inline with text |
| **Medium** | 24px | Standard buttons, list items |
| **Large** | 32px | Action bar, empty states |
| **XL** | 48px | Hero icons |

### Key Icons

| Action | Icon |
|--------|------|
| Like | `Icons.favorite` |
| Dislike | `Icons.close` |
| Undo | `Icons.undo` |
| Share | `Icons.share` |
| Settings | `Icons.settings` |
| Back | `Icons.arrow_back` |
| External link | `Icons.open_in_new` |
| Admin | `Icons.admin_panel_settings` |
| Vote up | `Icons.thumb_up` |
| Vote down | `Icons.thumb_down` |
| Comment | `Icons.chat_bubble_outline` |
| Suggest | `Icons.add_link` |
| Featured | `Icons.star` |
| Trending | `Icons.trending_up` |
| Campaign | `Icons.campaign` |

---

## 10. Accessibility

### Touch Targets

- Minimum: 48x48px
- Recommended: 56x56px for primary actions

### Color Contrast

- Text on background: 4.5:1 minimum
- Large text: 3:1 minimum
- Interactive elements: 3:1 minimum

### Screen Reader

```dart
// Always provide semantics
Semantics(
  label: 'Like this product',
  button: true,
  child: IconButton(...),
)

// Images
CachedNetworkImage(
  semanticLabel: productTitle,
  ...
)

// Featured badge
Semantics(
  label: 'Sponsored product',
  child: FeaturedBadge(),
)
```

### Focus

```dart
// Ensure focusable
Focus(
  child: GestureDetector(...),
)

// Visible focus indicator
focusColor: Theme.of(context).colorScheme.primary.withOpacity(0.12)
```

---

## 11. Error States

### Empty States

```dart
Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
      SizedBox(height: 16),
      Text(
        'No items yet',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      SizedBox(height: 8),
      Text(
        'Start swiping to discover furniture',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.grey,
        ),
      ),
    ],
  ),
)
```

### Loading States

```dart
// Shimmer placeholder for cards
Shimmer.fromColors(
  baseColor: Colors.grey[300]!,
  highlightColor: Colors.grey[100]!,
  child: Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
  ),
)

// Centered spinner for full-page load
Center(child: CircularProgressIndicator())
```

### Error Messages

```dart
// Inline error
Text(
  errorMessage,
  style: TextStyle(color: Theme.of(context).colorScheme.error),
)

// Snackbar
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Something went wrong'),
    action: SnackBarAction(
      label: 'Retry',
      onPressed: onRetry,
    ),
  ),
)
```

---

## 12. Folder Structure

```
lib/
├── core/
│   ├── router.dart       # go_router config
│   ├── theme.dart        # ThemeData
│   ├── spacing.dart      # Spacing constants
│   └── constants.dart    # App-wide constants
├── data/
│   ├── api_client.dart   # Dio HTTP client
│   ├── hive_store.dart   # Local persistence
│   └── models/           # Data classes
├── features/
│   ├── deck/
│   │   ├── deck_screen.dart
│   │   └── widgets/
│   │       ├── swipe_card.dart
│   │       └── premium_image_card.dart
│   ├── likes/
│   ├── decision_room/
│   │   ├── decision_room_screen.dart
│   │   └── widgets/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   ├── settings/
│   ├── admin/
│   └── console/          # Retailer console
│       ├── home/
│       ├── campaigns/
│       ├── catalog/
│       ├── trends/
│       └── reports/
└── shared/
    ├── widgets/          # Reusable widgets
    └── extensions/       # Dart extensions
```

---

## 13. Code Style

### Widget Naming

- Screens: `*Screen` (e.g., `SwipeScreen`)
- Reusable widgets: Descriptive noun (e.g., `ProductCard`)
- Providers: `*Provider` or `*Notifier`

### File Naming

- Snake case: `swipe_screen.dart`
- One public widget per file
- Co-locate tests: `swipe_screen_test.dart`

### Imports

```dart
// Order: dart, flutter, packages, relative
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import 'swipe_card.dart';
```

---

## References

- [APP_FLOW.md](APP_FLOW.md) – Navigation and screens
- [TECH_STACK.md](TECH_STACK.md) – Package versions
- [BACKEND_STRUCTURE.md](BACKEND_STRUCTURE.md) – API contracts
- [COMMERCIAL_STRATEGY.md](COMMERCIAL_STRATEGY.md) – Featured and scoring UI
