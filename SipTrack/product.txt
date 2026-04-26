# SipTrack (Tracksip) — Complete Product Specification

## Part 1: Screen-by-Screen UI/UX Specification

### 1. Home Screen (app/index.tsx)

**Screen Purpose:** Dashboard displaying user's drinking activity, upcoming events, and quick access to pro features.

**Header Section:**
- Greeting text (16px, semibold, text color) that changes by hour:
  - 5:00 AM - 11:59 AM: "Good morning"
  - 12:00 PM - 5:59 PM: "Good afternoon"
  - 6:00 PM - 4:59 AM: "Good evening"
- No explicit subtitle visible on hero section

**Active Event Card (Hero):**
- Background: surfaceElevated (#1C1C2E)
- Border: 1px border color (#2A2A3A)
- Rounded: border-radius 12px
- Padding: 16px all sides
- Content (if active event exists):
  - Red badge with white text: "LIVE" (10px, bold)
  - Pulsing animation on LIVE badge: opacity 0.6 → 1.0, 1.5s duration, repeat infinite
  - Event name: 24px, bold (700), text color
  - Event time: "Started at HH:MM AM/PM" format (14px, secondary text)
  - Large stat display: Total drinks count (44px, bold, accent color #F0A830)
  - Bar underneath: "in Xm (Xh XXm)" showing elapsed duration (14px, secondary)
  - "View" button: accent background, "chevron-forward" icon, 44px height
- Content (if no active event):
  - Icon: "sparkles-outline" (32px, accent color)
  - Text: "Start a new night" (16px, semibold)
  - Button: "Start night" (accent background, full width)

**Feature Grid (2×2):**
- Visible only on free tier; pro tier shows different content
- 4 cards in grid layout (2 columns, 2 rows), gap 8px
- Card styling: surface background, border 1px, border-radius 12px, padding 12px
- Cards (in order): Calendar, Stats, Goals, Drinks
- Each card has:
  - Icon (24px, accent color) in top-left
  - Label (12px, secondary text, all-caps)
  - "PRO" badge (orange background, white text, 8px padding, 10px font, semibold)
  - Chevron icon (bottom-right, 20px, tertiary text)
- Tap behavior: navigates to respective pro screen with paywall overlay

**Free Feature Badges (Alternative Layout for Pro Users):**
- Replaced with 3-card row showing active features
- Same card styling as above
- Icons and labels only (no "PRO" badge)

**Event History Section:**
- Title: "Recent nights" (14px, semibold)
- FlatList with events in reverse chronological order
- Free tier: limited to 30 days of history (enforced on data fetch)
- Ad injection: Native card ad appears after 4th event (using Google AdMob)
- Each event item:
  - Date badge: left side, light background, contains formatted date "MMM DD"
  - Event name: 14px, bold, text color
  - Metadata row: "HH:MM AM/PM – Xm duration · X drinks" (12px, secondary text)
  - Right chevron: navigation indicator (20px, tertiary)
  - Tap navigates to app/summary/[id]
- Empty state (when no events):
  - Icon: "sparkles-outline" (48px, secondary text)
  - Text: "No nights yet" (16px, semibold)
  - Subtext: "Start a night to begin tracking" (14px, secondary)
  - Button: "Start my first night" (accent background)
  - Centered, with 32px bottom margin

**Bottom Navigation:**
- Implicit from Expo Router setup; visible screens include Home, Calendar (pro), Dashboard (pro), Challenges (pro), Drinks (pro), Profile

---

### 2. Active Event Screen (app/event/[id].tsx)

**Screen Purpose:** Real-time tracking of a drinking event with live BAC calculation, hydration, drink logging, and timeline.

**Header:**
- Title: event name (16px, bold) in top-left
- "Stop night" button: secondary styling, top-right (secondary background, secondary border, secondary text)
- Conditional red banner below header (only if driving mode is enabled AND BAC status is "red" per intoxication stages):
  - Full-width banner, red background (#FF4757), white text
  - Text: "DO NOT DRIVE" (14px, bold)
  - Icon: alert-circle (16px, white)

**Stats Row (4 Cards in Horizontal Scroll):**
- Layout: scrollable horizontal view, 4 equal-width cards
- Card styling: surface background, border 1px, border-radius 8px, padding 12px
- Content per card:
  1. Total drinks: large number (28px, bold, accent), label "Total drinks" (10px, secondary)
  2. Alcohol grams: large number (28px, bold, accent), label "g pure alcohol" (10px, secondary)
  3. Standard drinks: large number (28px, bold, accent), label "standard drinks" (10px, secondary)
  4. Calories: large number (28px, bold, accent), label "kcal total" (10px, secondary)

**Intoxication Section:**
- Title: "Intoxication level" (12px, secondary)
- Progress bar: full width, height 32px, border-radius 8px
- Bar segments: 7 colored segments representing intoxication stages (listed below)
- Segment widths: proportional to BAC ranges
  - Sober (0-0.02%): #2ED573 (green)
  - Buzzed (0.02-0.05%): #7BED9F (light green)
  - Tipsy (0.05-0.08%): #FFD43B (yellow)
  - Impaired (0.08-0.15%): #FFA502 (orange)
  - Drunk (0.15-0.25%): #FF6B35 (red-orange)
  - Very drunk (0.25-0.35%): #FF4757 (red)
  - Danger (0.35-0.50%): #C0392B (dark red)
- Pointer indicator: vertical line at current BAC position, white color, height extends full bar
- Limit tick (if driving mode enabled): vertical line at selected BAC limit (0.05% or 0.08%), yellow color, height extends full bar
- Scale labels: min "0.0%", max "0.5%" at bar edges (10px, secondary)

**Hydration Card (if hydration tracking enabled):**
- Background: surface, border 1px
- Border-radius: 12px
- Padding: 12px
- Header: water icon (20px, accent) + "Hydration" label (12px, secondary)
- Content: "X / Y drinks" (16px, bold, text color)
- Subtext: hydration level label (12px, color-coded):
  - "Behind on water" (red #FF4757)
  - "Good hydration" (green #2ED573)
  - "Great hydration" (accent #F0A830)
- Button: "Water" (secondary styling, 40px height, water-outline icon)

**Water Nudge Animated Card (if hydration ratio threshold met):**
- Animation: FadeInDown (200ms), FadeOutDown (200ms) on exit
- Auto-dismiss: 8 seconds
- Content: "💧 Time for some water!" (14px, accent color)
- Z-index: above other content
- Position: top-center, with 16px top margin
- Can be manually dismissed with X button

**Drink Breakdown Section:**
- Horizontal scrollable chips showing drink type breakdown
- Chip format: "Name: X" (12px, semibold, accent color background, dark text)
- Example: "Beer: 3", "Wine: 1"
- Gap between chips: 8px

**Quick-Add Drinks Grid:**
- Title: "Add drinks" (12px, secondary)
- Grid: 3 columns, auto-rows
- Each drink card:
  - Icon: 44px square, accentDim background (#F0A830 with 15% opacity), border-radius 8px
  - Name: 14px, semibold, ellipsis on overflow
  - Info row: "XYZml · ABC% ABV" (11px, secondary)
  - Calorie info: "XYZ kcal" (11px, secondary)
  - Tap to add 1 quantity of drink to event

**Timeline Section:**
- Title: "Timeline" (12px, secondary)
- Reverse chronological order (newest first)
- Each drink entry:
  - Icon: drink-specific icon (20px, accent)
  - Name: 14px, semibold
  - Quantity suffix: " x1", " x2", etc. (12px, secondary)
  - Comment: if present, displayed on new line (12px, secondary italic)
  - Timestamp: right side (12px, secondary)
  - Tap to edit (navigates to app/edit-entry with entry ID)
- Each water entry:
  - Icon: water icon (20px, accent)
  - Label: "Water" (14px, semibold)
  - Volume: "XYZml" (12px, secondary)
  - Timestamp: right side (12px, secondary)

**Undo Bar (after drink added):**
- Animation: FadeInDown (200ms), auto-dismiss FadeOutDown (200ms) after 5 seconds
- Position: top-center above timeline
- Background: accentDim, border-radius 8px
- Content: "Drink added" text + "Undo" button (secondary)
- Z-index: above timeline but below modals

**BAC Alert Modal (if driving mode and BAC exceeds limit):**
- Overlay: semi-transparent dark background
- Card: surface background, border-radius 12px, padding 16px, centered
- Icon: alert-circle (32px, red #FF4757)
- Title: "Don't drive" (18px, bold)
- Message: "Your BAC has reached {limit}%. It's not safe to drive." (14px, secondary)
- Disclaimer: "Always use a designated driver or rideshare service." (12px, tertiary, italic)
- Button: "Got it" (accent background, full width)

---

### 3. Event Summary Screen (app/summary/[id].tsx)

**Screen Purpose:** Post-event detailed analysis with breakdown, BAC metrics, calorie impact, and night notes.

**Hero Card:**
- Background: accentDim with 30% opacity
- Border: 2px accentGlow (#F0A830 with 30% opacity)
- Padding: 16px
- Border-radius: 12px
- Event name: 24px, bold, text color
- Full date format: "dddd, MMMM DD, YYYY" (e.g., "Friday, April 26, 2024") (14px, secondary)
- Time range: "HH:MM AM/PM – HH:MM AM/PM" or "Ongoing" if event not ended (14px, secondary)

**Big Stats Row:**
- Two columns with divider
- Left: drink count (44px, bold, accent) + "drinks" label (12px, secondary)
- Divider: vertical 1px line, secondary color
- Right: duration (44px, bold, accent) + "Xh XXm" label (12px, secondary)

**Breakdown Section:**
- Title: "Breakdown" (12px, secondary)
- Per-drink bar chart (repeated for each drink type with count > 0):
  - Layout: 3 columns (name | bar | count)
  - Name: 70px left column, 14px, bold, text color
  - Bar: flex 1, height 8px, border-radius 4px, filled color (accent), percentage based on (count / total) * 100%
  - Count: right column, 16px, bold, accent color
  - Gap between bars: 8px

**Alcohol Section:**
- Row 1: "{grams.toFixed(1)}g pure alcohol" (14px, bold) + "{standardDrinks.toFixed(1)} standard drinks" (14px, secondary)
- Row 2: "{calories} total calories" (14px, semibold)

**Hydration Card (if applicable):**
- Background: accentDim, border 1px secondary
- Padding: 12px
- Border-radius: 8px
- Content:
  - Icon + "X glasses of water" (14px, bold)
  - Ratio display: "X : Y ratio" (12px, secondary)
  - Hydration level badge: colored pill (background accentDim, text color based on level)
  - Disclaimer: "Water doesn't speed up alcohol metabolism, but helps you feel better." (10px, tertiary, italic)

**BAC Section (if driving mode enabled):**
- Two metric cards (side-by-side on wide screens, stacked on mobile):
  1. "Peak BAC": large value (44px, bold, accent) + "Xh XXm after start" timestamp (12px, secondary)
  2. "Time to 0.00%": large value (44px, bold, accent) + time duration (12px, secondary)
- Warning card (if peak BAC exceeded limit): red background, warning icon, "You exceeded your limit by 0.XX%" text
- Disclaimer: "Calculations assume Watson formula; always drink responsibly." (10px, tertiary, italic)

**Calorie Impact Section:**
- Hero value: "{calories}" (44px, bold, accent color)
- Percentage of daily intake: "XX% of daily calorie intake" (14px, secondary)

**Pro-Gated Calorie Equivalencies (if pro user):**
- Title: "Calorie equivalencies" (12px, secondary)
- Food comparisons grid (2 columns):
  - Per item: emoji (20px) + name (14px, bold) + count (12px, secondary) + kcal per unit (11px, tertiary)
  - Example: "🍔 Big Mac" "4" "563 kcal each"
- Exercise comparisons:
  - Per item: icon (20px, accent) + name (14px, bold) + horizontal bar (flex 1, height 6px) + time (12px, secondary)
  - Example: "Running 1h 15m"
- Reality facts card (surface background, border 1px, padding 12px, border-radius 8px):
  - Content: randomly selected fact string from calorie facts array (12px, secondary italic)

**Free Tier Teaser (if free tier user):**
- Icon: lock-closed (24px, secondary)
- Text: "See food & exercise equivalents" (14px, semibold)
- Button: "Unlock with Pro" (accent background, full width)
- Fine print: "$1.99/month · $19.99/year" (10px, tertiary)

**Night Notes Section:**
- Icon: document-text-outline (20px, secondary)
- TextInput: multiline, placeholder "Add notes about this night..." (14px, text color)
- Conditional buttons:
  - If text changed: "Save" button (accent background)
  - If recently saved: "Saved" badge (success background, checkmark icon, 12px)
- Border-radius: 8px, border 1px secondary, padding 12px

**Your Night Section:**
- Title: "Your night" (12px, secondary)
- Generated prose: AI-generated text summary of the event (14px, text color, line-height 1.5)
- Share button: "Share" (secondary styling, share-social icon)
  - On native: uses Share.share() API to open native share sheet
  - On web: uses clipboard.writeText() to copy to clipboard, shows toast confirmation

---

### 4. Profile Screen (app/profile.tsx)

**Screen Purpose:** User settings including physical attributes, notification preferences, subscription management, and account actions.

**Section: Personal Info**
- Title: "Personal info" (12px, secondary)

- Sex segmented control:
  - 3 buttons: "Male", "Female", "Prefer not to say"
  - Inactive state: surface background, border 1px secondary, secondary text, 14px
  - Active state: accentDim background, border 2px accent, bold text (600 weight), 14px
  - Border-radius: 8px per button
  - Height: 44px per button
  - Layout: full width, 3 equal columns with 8px gap

- Weight input:
  - Label: "Weight (kg)" (12px, secondary)
  - TextInput: numeric, validation 35-200 kg, max 3 characters
  - Placeholder: "e.g. 70"
  - Normal state: border 1px secondary, padding 12px, border-radius 8px
  - Error state: border 2px red (#FF4757), background with 10% red opacity
  - Error message displayed below: "Enter weight between 35–200 kg" (11px, red)

- Height input:
  - Label: "Height (cm, optional)" (12px, secondary)
  - TextInput: numeric, validation 100-230 cm, max 3 characters
  - Placeholder: "e.g. 180"
  - Same styling as weight

- Birth year input:
  - Label: "Birth year (optional)" (12px, secondary)
  - TextInput: numeric, validation 1900 to current year, max 4 characters
  - Placeholder: "e.g. 1990"
  - Same styling as weight

**Section: Hydration & Notifications**
- Hydration toggle:
  - Icon: water-outline (20px, secondary)
  - Label: "Suggest water between drinks" (14px, text color)
  - Switch: 44px width, 26px height, thumb diameter 20px, accent color when on
  - Tap to enable/disable water suggestions

- Notifications master toggle:
  - Icon: notifications-outline (20px, secondary)
  - Label: "Enable pace warnings" (14px, text color)
  - Switch: same styling as hydration
  - Conditional nested options appear when enabled:
    - Drinks per hour input (numeric, 1-20 range, editable only if enabled)
    - Label: "Warn me if I'm drinking faster than" (12px, secondary)
    - Input field with unit "drinks/hour" (12px, secondary)

- BAC approach toggle (nested under notifications):
  - Label: "Warn if approaching BAC limit" (14px, text color)
  - Switch: accent color

- Intoxication stage toggle (nested under notifications):
  - Label: "Warn on intoxication stage change" (14px, text color)
  - Switch: accent color

- Calorie budget input (nested under notifications):
  - Label: "Calorie goal per event" (12px, secondary)
  - TextInput: numeric, editable only if notifications enabled
  - Unit: "kcal" (12px, secondary)

**Info Card:**
- Background: accentDim, border 1px secondary
- Padding: 12px
- Border-radius: 8px
- Content: "These calculations are estimates based on the Watson and Widmark formulas. Always drink responsibly and use a designated driver if needed." (10px, tertiary, italic)

**Subscription Card:**
- Background: accentDim, border 1px accent
- Padding: 16px
- Border-radius: 12px
- Content:
  - Icon (if not pro): lock-closed (24px, secondary) OR (if pro) sparkles (24px, accent)
  - Title: "SipTrack Pro" (16px, bold)
  - Subtitle (if not pro): "Unlock full tracking, challenges, and insights" (12px, secondary)
  - Subtitle (if pro): "{tier} · since {date}" (12px, secondary) - e.g., "Lifetime · since Apr 26, 2024"
  - Chevron icon: right side (20px, secondary)
  - Tap navigates to app/pricing

**Account Section:**
- Title: "Account" (12px, secondary)
- Email display:
  - Label: "Email" (12px, secondary)
  - Value: user email address (14px, text color, can be selected/copied)
- Sign out button:
  - Text: "Sign out" (14px, secondary)
  - Background: dangerDim (red with 15% opacity)
  - Border: 1px red (#FF4757)
  - Tap shows confirmation modal, then signs out
- Delete my account button:
  - Text: "Delete my account" (14px, secondary)
  - Background: dangerDim
  - Border: 1px red
  - States:
    - Normal: clickable
    - Loading: shows ActivityIndicator, button disabled
    - After delete: navigates to auth screen
  - Confirmation: modal with warning text and confirmation required

---

### 5. Pricing Screen (app/pricing.tsx)

**Screen Purpose:** Display subscription tiers and manage Pro upgrade or restoration.

**Hero Section:**
- Icon: sparkles-outline (48px, accent) inside accentDim circle (72px diameter)
- Circle border: 2px accentGlow
- Title: "Unlock SipTrack Pro" (24px, bold, letter-spacing -0.3)
- Subtitle: "Advanced tracking, insights & challenges" (14px, secondary)
- Spacing: 16px between icon and title, 8px between title and subtitle

**Tier Cards (side-by-side row, full width):**
- Free card:
  - Background: surface, border 1px secondary
  - Padding: 12px
  - Border-radius: 12px
  - Title: "Free" (14px, bold)
  - Icon: dash-circle-outline (20px, secondary)
  - Checkmarks: 5 features listed with checkmark icons (12px, secondary)

- Pro card:
  - Background: surface with gradient overlay (accentGlow with 20% opacity)
  - Border: 2px accentGlow
  - Padding: 12px
  - Border-radius: 12px
  - Badge: "BEST VALUE" (9px, bold, white text, accent background, positioned top-right)
  - Title: "Pro" (14px, bold, accent color)
  - Icon: sparkles-outline (20px, accent)
  - Checkmarks: 6 features listed with checkmark icons (12px, accent)

**Period Toggle (visible only if user is not already pro):**
- 3 buttons: "Monthly", "Yearly", "Lifetime"
- Inactive: surface background, border 1px secondary
- Active: accentDim background, border 2px accent
- Price displayed on 2nd line: "$1.99", "$19.99", "$59.99"
- Font: 12px, semibold
- Border-radius: 8px
- Height: 44px per button
- Layout: full width, 3 equal columns with 8px gap

**Subscribe Button (if not pro):**
- Full width
- Accent background
- Height: 48px
- Border-radius: 8px
- Font: 15px, bold, white
- Icon: arrow-forward (right side)
- Text: "Get Lifetime — $59.99" (lifetime) OR "Subscribe — $1.99/mo" (monthly) OR "Subscribe — $19.99/yr" (yearly)
- Tap: initiates RevenueCat purchase flow

**Signin Hint (web only):**
- Visible only on web platform
- Text: "Subscriptions are available on iOS and Android." (12px, secondary)
- Displayed below subscribe button

**Restore Button:**
- Text: "Restore purchases" (14px, secondary)
- States:
  - Normal: clickable, secondary text styling
  - Loading: text replaced with ActivityIndicator
- Spacing: 16px below subscribe button

**Active Pro Card (if user is already pro):**
- Background: accentDim, border 1px accent
- Padding: 16px
- Border-radius: 12px
- Icon: checkmark-circle (24px, success color #2ED573)
- Text:
  - "You're on Pro" (16px, bold)
  - "{period} · since {date}" (12px, secondary) - e.g., "Lifetime · since Apr 26, 2024"
- Manage button:
  - Text: "Manage subscription" (14px, secondary)
  - Styling: secondary background, border 1px secondary
  - Height: 44px, border-radius 8px
  - Tap: opens native subscription management (iOS: App Store, Android: Google Play)

**Disclaimer Text:**
- "Subscriptions auto-renew unless cancelled in your device settings. Annual plans renew yearly, monthly plans monthly." (10px, tertiary, italic)
- Positioned at bottom

---

### 6. Calendar Screen (app/calendar.tsx) [PRO-GATED]

**Screen Purpose:** Monthly overview of drinking activity with day-by-day intensity visualization.

**Month Selector:**
- Layout: chevron-back | month/year text | chevron-forward
- Chevrons: 24px, secondary, 44px tap target
- Text: "April 2024" (bold 16px, text color, min-width 160px, centered)
- Tap chevrons to navigate months

**Month Stats Row:**
- 3 mini stat cards side-by-side
- Card content:
  1. "Active nights" + count (12px label, 24px bold value)
  2. "Total drinks" + count
  3. "Total calories" + count
- Background: surface, border 1px secondary, border-radius 8px, padding 8px
- Font: 10px label, 16px bold value
- Text: secondary and accent colors

**Calendar Grid:**
- 7 columns for days of week (Mon-Sun headers, 11px, semibold, secondary)
- 6 rows of days (42 day cells)
- Day cell styling (36×36, border-radius 50% circle, centered text):
  - Background: none (transparent) if no activity
  - Background color (intensity gradient) if activity:
    - 1-2 drinks: 20% opacity accent (#F0A830)
    - 3-5 drinks: 45% opacity accent
    - 6+ drinks: 80% opacity accent
  - Text: day number (12px, bold, text color)
  - Today border: 1.5px accent, if today's date
  - Selected border: 2px text color, if day is selected
  - Note dot: 4×4 circle (accent color) positioned bottom-right if notes exist for day

**Legend:**
- "Intensity:" label (11px, secondary)
- 3 dot indicators with labels:
  - Low: 4px dot (20% accent) + "1-2" (10px, secondary)
  - Mid: 4px dot (45% accent) + "3-5" (10px, secondary)
  - High: 4px dot (80% accent) + "6+" (10px, secondary)

**Day Detail Panel (bottom sheet or sidebar):**
- Title: selected day's date (14px, bold)
- For each event on selected day:
  - Card: surface background, border 1px secondary, padding 12px, border-radius 8px
  - Icon: moon-outline (16px, accent)
  - Name: 14px, bold, flex 1
  - Metadata: "Xm · X drinks" (12px, secondary)
  - Note indicator: document-outline icon (16px, secondary) if notes exist
  - Chevron: right side (16px, secondary) for navigation
  - Tap navigates to summary screen for that event

**Empty Hint (when no day selected):**
- Icon: hand-left-outline (48px, secondary)
- Text: "Tap a day with activity to see details" (14px, secondary)
- Centered, with spacing

---

### 7. Dashboard Screen (app/dashboard.tsx) [PRO-GATED]

**Screen Purpose:** Advanced analytics with all-time and monthly statistics, trends, and insights.

**Tab Row:**
- Two buttons: "All time" | "Monthly"
- Inactive: transparent background, secondary text, 14px
- Active: accentDim background, accent border (1px), accent text, 14px bold
- Height: 44px, border-radius 8px, gap 8px
- Layout: flex row, space-between

**All Time Tab Content:**

- Stats grid (3×2, gap 12px):
  1. "Total nights" + count (12px label, 28px bold value, accent color)
  2. "Average drinks per night" + value (12px label, 28px bold value)
  3. "Favorite drink" + name (12px label, 14px bold value)
  4. "Busiest day" + day name (12px label, 14px bold value)
  5. Wide stat card: "Record night" + drink count + date (surface bg, border 1px, padding 12px, border-radius 8px)
  6. Wide stat card: "Streaks" + "X day weekly" + "X day weekend" (surface bg, border 1px, padding 12px, border-radius 8px)

- Insights card:
  - Background: accentDim, border 1px accent, padding 12px, border-radius 8px
  - Title: "Insights" (12px, secondary)
  - Content: generated insight text (12px, text color)
  - Icon: bulb-outline (16px, accent)

**Monthly Tab Content:**

- Month selector (same as calendar): chevron-back | month/year | chevron-forward
- Stats grid (3 columns, similar to all-time but scoped to month)
- Best/worst night cards: "Best night" and "Worst night" with date and drink count
- Bar charts:
  - By drink type (horizontal bars, names left, bars flex 1, values right)
  - By week (vertical bars for each week of month, heights proportional to drink count, bar-radius 4px top)

---

### 8. Challenges Screen (app/challenges.tsx) [PRO-GATED]

**Screen Purpose:** Goal setting and progress tracking for drinking limits and challenges.

**Empty State (if no challenges):**
- Icon: trophy-outline (48px, secondary)
- Title: "No challenges yet" (16px, bold)
- Subtext: "Set a goal to get started" (12px, secondary)
- Button: "Create challenge" (accent background, arrow-forward icon)

**Challenge Cards (for each active challenge):**
- Background: surface, border 1px secondary
- Padding: 12px
- Border-radius: 8px
- Layout: 3 columns (icon | content | status)
- Icon column: challenge-specific icon (36×36) inside surfaceElevated circle, border-radius 8px
- Content column (flex 1):
  - Title: 14px, bold
  - Label: 12px, secondary
- Status column:
  - Badge: "Active", "Completed", "Failed", or "Expired" (10px, bold, color-coded background)
  - Below badge: progress bar (height 6px, border-radius 3px, full width of card)
  - Bar color: accent if active, success if completed, danger if failed/expired
  - Bar fill: percentage based on challenge progress

**Create Challenge Modal:**
- Overlay: semi-transparent
- Card: surface background, border 1px secondary, padding 16px, border-radius 12px
- Title: "New challenge" (18px, bold)
- Subtitle: "What do you want to track?" (12px, secondary)
- Challenge type list (scrollable):
  - 5 challenge types, each a card:
    1. "Max drinks per week" (icon + name + description)
    2. "Max nights per month"
    3. "Dry week"
    4. "Max drinks per night"
    5. "Max calories per week"
- Selected type details:
  - Description: 12px, secondary
  - Target input (if not dry_week): numeric input, "Target: X {unit}" (12px, secondary)
  - Duration info: "This challenge runs for X days until {end_date}" (11px, tertiary)
  - "Start challenge" button: accent background, full width, 44px height

**Navigation:**
- Back button: left side, chevron-back icon (24px, secondary)
- Title: "Challenges" (16px, bold)
- Add button (if not empty state): right side, add-circle-outline (36×36, accent background circle)

---

### 9. Drinks Screen (app/drinks.tsx) [PRO-GATED]

**Screen Purpose:** View and customize the drink database for the event.

**Header:**
- Back button: chevron-back (24px, secondary), 44px tap target
- Title: "Drinks" (16px, bold)
- Subtext: "{count} total · tap to edit" (12px, secondary)
- Add button: add-circle-outline (36×36) inside accent circle, top-right

**Drinks Grid (2 columns, gap 8px):**
- Per drink card:
  - Icon: 44×44 square, accentDim background, border-radius 8px, icon 24px centered
  - Name: 14px, bold, ellipsis on overflow, 2px line-height
  - Stats chips:
    - "{volume}ml" (10px, secondary background, secondary text, border-radius 4px, padding 4px)
    - "{abv}% ABV" (10px, secondary background, secondary text)
    - "{calories} kcal" (10px, secondary background, secondary text)
  - Volume info (if custom): "Custom volume" (11px, tertiary)
  - Spacing: 8px vertical gap between elements
  - Tap to edit navigates to app/edit-drink/[id]

---

### 10. Create Event Screen (app/create-event.tsx)

**Screen Purpose:** Initialize a new drinking event with basic details and optional driving mode setup.

**Name Input:**
- Label: "Event name" (12px, secondary)
- TextInput: placeholder "e.g. Friday with friends" (14px, text color)
- Border: 1px secondary, padding 12px, border-radius 8px

**Info Row:**
- Two segments (flexed columns):
  - Date segment: calendar-outline icon (16px, secondary) + date picker (tap to open modal with date selector)
  - Time segment: time-outline icon (16px, secondary) + time input showing "HH:MM AM/PM" (14px, text color)

**Driving Mode Toggle:**
- Icon: car-outline (20px, secondary)
- Title: "I'm driving" (14px, bold)
- Description: "Get warnings if BAC gets too high" (12px, secondary)
- Toggle switch: 44×26, accent color when on

**BAC Limit Section (appears only if driving mode enabled):**
- Label: "BAC Limit" (12px, secondary)
- Two option buttons (full width, 44px height, gap 8px):
  1. "0.05% Conservative" (14px, semibold, secondary background, border 1px secondary, selected=accent background+border)
  2. "0.08% Standard" (14px, semibold, secondary background, border 1px secondary, selected=accent background+border)
- Hint text: "Select your local legal limit" (11px, tertiary)
- Warning card (if 0.08% selected and user in conservative region):
  - Background: dangerDim (red with 15% opacity)
  - Icon: alert-circle-outline (16px, red #FF4757)
  - Text: "Check your local laws" (12px, red)

**Active Event Warning (if an event is already active):**
- Card: dangerDim background, border 1px red
- Icon: alert-circle-outline (16px, red)
- Text: "You already have an active night. End that one first." (12px, red)

**"Start night" Button:**
- Accent background, full width, 48px height
- "Start night" text (15px, bold, white)
- Arrow-forward icon (right side, 20px, white)
- Border-radius: 8px
- Tap: validates inputs, shows profile setup modal if driving mode but profile incomplete, then creates event

**Profile Setup Modal (conditional, driving mode + incomplete profile):**
- Overlay: semi-transparent
- Card: surface background, padding 16px, border-radius 12px
- Title: "Complete your profile" (16px, bold)
- Subtitle: "Required for accurate BAC calculations" (12px, secondary)
- Sex segmented control (3 buttons): "Male", "Female", "Prefer not to say" (same styling as profile screen)
- Weight input: numeric, 35-200 kg, "Weight (kg)" label (12px, secondary)
- "Save & enable" button: accent background, full width
- "Cancel" button: secondary styling

---

### 11. Edit Entry Screen (app/edit-entry.tsx)

**Screen Purpose:** Modify quantity, comment, or delete a logged drink/water entry.

**Drink Info Row:**
- Drink icon (24px, accent)
- Drink name (bold 16px, text color, flex 1)
- Time (13px, tertiary, right side)

**Quantity Stepper:**
- Layout: minus button | value | plus button
- Buttons: 48×48, accentDim background, border 1px secondary, border-radius 8px
- Minus button icon: remove-circle-outline (20px, secondary)
- Plus button icon: add-circle-outline (20px, secondary)
- Value display: center, bold 28px, accent color

**Comment Input:**
- Label: "Comment (optional)" (12px, secondary)
- TextInput: placeholder "e.g. felt strong", multiline
- Border: 1px secondary, padding 12px, border-radius 8px
- Max length: typically 200 characters

**Actions Row (bottom):**
- Save button: flex 1, accent background, white text, 48px height, border-radius 8px, "Save" (14px, bold)
- Delete button: 52×52, dangerDim background, border 1px red, trash-bin-outline icon (20px, red), border-radius 8px

---

### 12. Edit Drink Screen (app/edit-drink.tsx) [PRO-GATED]

**Screen Purpose:** Customize drink properties for the database.

**Live Preview Card:**
- Background: accentDim, border 1px accent
- Padding: 12px
- Border-radius: 8px
- Layout: icon | content
- Icon: 52×52 square, accentDim background, border-radius 8px, icon centered
- Content:
  - Name: 14px, bold, text color
  - Metadata: "{ml}ml · {abv}% ABV · {kcal} kcal · {stdDrinks} std" (11px, secondary)

**Name Input:**
- Label: "NAME" (12px, secondary, all-caps)
- TextInput: Inter 400 Regular 16px
- Border: 1px secondary, padding 12px, border-radius 8px
- Max length: 30 characters

**Stats Row (3 flex columns with dividers):**
- Column 1: Volume
  - Label: "ML" (10px, secondary, all-caps)
  - TextInput: numeric, placeholder "e.g. 355"
  - Unit: "ml" (12px, secondary)
  - Hint: "355ml" (10px, tertiary)
  - Divider: vertical 1px secondary (right edge)
- Column 2: Alcohol by Volume
  - Label: "ABV %" (10px, secondary, all-caps)
  - TextInput: numeric, placeholder "e.g. 5.0"
  - Unit: "%" (12px, secondary)
  - Divider: vertical 1px secondary (right edge)
- Column 3: Calories
  - Label: "KCAL" (10px, secondary, all-caps)
  - TextInput: numeric, placeholder "e.g. 153"
  - Unit: "kcal" (12px, secondary)

**Icon Picker:**
- Label: "ICON" (12px, secondary, all-caps)
- Horizontal scrollable row of 16 icon options
- Each icon: 48×48 circle, surface background, border 1px secondary
- Selected icon: accentDim background, border 2px accent
- Icons: beer, wine-bottle, shot-glass, champagne, cocktail, etc. (total 16 options)
- Tap to select

---

### 13. Paywall Component (components/Paywall.tsx)

**Screen Purpose:** Overlay component displayed when accessing pro features without active subscription.

**Layout (centered card):**
- Icon wrap: 72×72 circle, accentDim background, border 2px accentGlow, border-radius 50%
- Icon inside: 32px, accent color
- Title: bold 24px, text color, letter-spacing -0.3
- Description: 14px, secondary
- CTA button:
  - sparkles-outline icon (16px, white) + "Unlock with Pro" (bold 15px, white)
  - Accent background, full width, 48px height, border-radius 8px
- Fine print: "$1.99/month · $19.99/year" (11px, tertiary)
- "See all plans" link: secondary text (12px), underlined, navigates to pricing screen
- Z-index: above page content
- Overlay: semi-transparent dark background

---

## Part 2: Data Types and Business Logic

### Core Type Definitions (lib/types.ts)

**DrinkType Interface:**
- `id`: string (UUID)
- `name`: string (e.g., "Beer", "Wine", "Vodka")
- `defaultVolumeMl`: number (e.g., 355 for beer)
- `defaultAbv`: number (percentage, e.g., 5.0 for beer)
- `caloriesPerServing`: number (e.g., 153 for beer)
- `isPreset`: boolean (true for built-in drinks, false for custom)
- `icon`: string (icon key name, e.g., "beer-outline")
- `userId`: string (UUID, null for preset drinks)

**DrinkEntry Interface:**
- `id`: string (UUID)
- `eventId`: string (UUID, foreign key)
- `drinkTypeId`: string (UUID, foreign key)
- `timestamp`: ISO 8601 string
- `quantity`: number (e.g., 2 for "2 beers")
- `comment`: string | null (user note about drink)
- `volumeOverrideMl`: number | null (if user customized volume)
- `abvOverride`: number | null (if user customized alcohol percentage)

**WaterEntry Interface:**
- `id`: string (UUID)
- `eventId`: string (UUID, foreign key)
- `timestamp`: ISO 8601 string
- `volumeMl`: number (default 250, can be customized)

**NightEvent Interface:**
- `id`: string (UUID)
- `userId`: string (UUID, foreign key)
- `name`: string (e.g., "Friday with friends")
- `startTime`: ISO 8601 string
- `endTime`: ISO 8601 string | null (null if ongoing)
- `createdAt`: ISO 8601 string
- `drivingMode`: boolean (true if driving mode enabled)
- `bacLimit`: number | null (0.05 or 0.08, null if not driving)
- `notes`: string | null (post-event notes)

**UserProfile Interface:**
- `id`: string (UUID, primary key, matches auth.users.id)
- `sex`: "male" | "female" | "prefer_not_to_say" (required for BAC calculation)
- `weightKg`: number (required for BAC calculation, 35-200 range)
- `heightCm`: number | null (optional, 100-230 range)
- `birthYear`: number | null (optional, 1900-current year)
- `bacLimit`: number (default 0.08, user's preferred BAC limit for alerts)
- `waterSuggestionsEnabled`: boolean (default true, show water nudges)
- `notifications`: NotificationPreferences object
- `disclaimerAcceptedAt`: ISO 8601 string | null
- `deviceId`: string (unique device identifier)
- `onboardingComplete`: boolean
- `subscriptionTier`: "free" | "pro" (default "free")
- `subscriptionPeriod`: "monthly" | "yearly" | "lifetime" | null
- `subscriptionStartedAt`: ISO 8601 string | null
- `updatedAt`: ISO 8601 string

**NotificationPreferences Interface:**
- `enabled`: boolean (master toggle for all pace warnings)
- `drinksPerHour`: number (1-20 range, threshold for warning, default 4)
- `caloriesPerNight`: number (default 2000, threshold for warning)
- `bacApproachWarning`: boolean (default true, warn if approaching limit)
- `stageChangeWarning`: boolean (default true, warn on intoxication stage change)

**Challenge Interface:**
- `id`: string (UUID)
- `userId`: string (UUID, foreign key)
- `type`: ChallengeType (enum)
- `target`: number (goal value, e.g., 10 for max_drinks_per_week)
- `startDate`: ISO 8601 string
- `endDate`: ISO 8601 string
- `createdAt`: ISO 8601 string
- `completed`: boolean (true if challenge was achieved)

**ChallengeType Enum:**
- `"max_drinks_per_week"`: max drinks in 7-day period
- `"max_nights_per_month"`: max nights in calendar month
- `"dry_week"`: 7 days with zero drinks (no target parameter)
- `"max_drinks_per_night"`: max drinks in single event
- `"max_calories_per_week"`: max calories in 7-day period

**INTOXICATION_STAGES Array:**
Each stage object contains:
- `stage`: string ("sober", "buzzed", "tipsy", "impaired", "drunk", "very_drunk", "danger")
- `minBac`: number (lower bound)
- `maxBac`: number (upper bound)
- `color`: hex string (#2ED573, #7BED9F, #FFD43B, #FFA502, #FF6B35, #FF4757, #C0392B)
- `description`: string (e.g., "Sober and alert")
- `label`: string (short label, e.g., "Sober")

**PRESET_DRINKS Array (16 drinks):**
1. Beer: 355ml, 5% ABV, 153 kcal, beer-outline icon
2. Light Beer: 355ml, 4% ABV, 110 kcal
3. IPA/Craft: 355ml, 6.5% ABV, 180 kcal
4. Red Wine: 150ml, 13% ABV, 125 kcal
5. White Wine: 150ml, 12% ABV, 120 kcal
6. Champagne: 150ml, 12% ABV, 120 kcal
7. Tequila (Shot): 44ml, 40% ABV, 110 kcal
8. Vodka (Shot): 44ml, 40% ABV, 105 kcal
9. Whiskey (Shot): 44ml, 40% ABV, 110 kcal
10. Mezcal (Shot): 44ml, 42% ABV, 120 kcal
11. Margarita: 210ml, 15% ABV, 160 kcal
12. Mojito: 180ml, 10% ABV, 150 kcal
13. Gin & Tonic: 250ml, 10% ABV, 180 kcal
14. Piña Colada: 270ml, 12% ABV, 380 kcal
15. Hard Seltzer: 355ml, 4.5% ABV, 95 kcal
16. Michelada: 355ml, 4.5% ABV, 150 kcal

---

### Core Algorithms and Calculations (lib/types.ts continued)

**BAC Estimation (Widmark Formula):**
```
estimateBAC(alcoholGrams, weightKg, sex, drinkingHours) returns number
- Widmark r values:
  - Male: 0.68
  - Female: 0.55
  - Prefer not to say: 0.615
- Formula: BAC = (alcoholGrams / (weightKg * r)) - (0.015 * drinkingHours)
- Returns number clamped to 0.0-0.5 range
- Accounts for alcohol elimination at 0.015% per hour
```

**Peak BAC Calculation:**
```
estimatePeakBAC(entries, weightKg, sex, eventStartTime) returns number
- Iterates through all drink entries in chronological order
- For each entry, calculates BAC assuming drinks were consumed at that timestamp
- Returns the highest BAC reached during event
- Used for peak BAC display on summary screen
```

**Hours to Zero BAC:**
```
hoursToZeroBAC(currentBAC) returns number
- Formula: currentBAC / 0.015 (hours)
- Example: 0.15 BAC → 10 hours to clear
- Used for "Time to 0.00%" display on summary
```

**Get Intoxication Stage:**
```
getIntoxicationStage(bac) returns {stage, label, color, description}
- Maps BAC to 7-stage spectrum
- Returns stage object with color for UI rendering
- Used for progress bar coloring and warnings
```

**Calculate Alcohol Content:**
```
calculateAlcohol(volumeMl, abv, quantity) returns {pureAlcoholMl, pureAlcoholG, standardDrinks}
- pureAlcoholMl = volumeMl * (abv / 100) * quantity
- pureAlcoholG = pureAlcoholMl * 0.789 (density of ethanol)
- standardDrinks = pureAlcoholG / 14 (US standard drink = 14g)
- Used for tracking total alcohol consumed
```

**Hydration Ratio Calculation:**
```
computeHydrationRatio(waterGlasses, drinkCount) returns number
- Ratio = waterGlasses / drinkCount
- Returns 0 if no drinks logged
- Thresholds:
  - 0-0.3: "behind" (red)
  - 0.3-0.7: "balanced" (yellow)
  - 0.7+: "great" (green)
- Used for hydration level badge coloring
```

**Apply Hydration to BAC:**
```
applyHydrationToBAC(bac, hydrationRatio) returns number
- MAX_HYDRATION_BAC_REDUCTION = 0.05 (5% max reduction)
- reductionFactor = Math.min(hydrationRatio * 0.1, 0.05)
- adjustedBAC = bac * (1 - reductionFactor)
- Note: Water does NOT speed up metabolism, only slight reduction to peak BAC
- Used for calculating adjusted BAC display in events with hydration
```

**Get Hydration Level:**
```
getHydrationLevel(ratio) returns "none" | "behind" | "balanced" | "great"
- none: 0 drinks, 0 water
- behind: ratio < 0.3
- balanced: 0.3 <= ratio < 0.7
- great: ratio >= 0.7
```

---

### Subscription Types and Constants (lib/subscription.ts)

**Pricing Constants:**
- `PRO_MONTHLY_USD = 1.99`
- `PRO_YEARLY_USD = 19.99`
- `PRO_LIFETIME_USD = 59.99`

**isPro Function:**
```
isPro(profile: UserProfile | null | undefined) returns boolean
- Returns profile?.subscriptionTier === 'pro'
- Used as guard for all pro-gated features
```

**PRO_FEATURES Array:**
- `extended_history`: "Full history" - See every past night, not just the last 30 days
- `calendar`: "Calendar view" - Monthly overview of drinking activity
- `dashboard`: "Stats & trends" - Weekly patterns, totals, and insights
- `challenges`: "Goals & challenges" - Set limits for drinks, nights, or calories
- `custom_drinks`: "Custom drinks" - Add and edit your own drink types
- `calorie_equivalencies`: "Calorie equivalencies" - See what your drinks equal in food and exercise

**FREE_FEATURES Array:**
- Track nights: Create events, log drinks, live BAC
- Driving mode: Set a BAC limit with live warnings
- Default drinks: Beer, wine, spirits, cocktails presets
- Hydration tracking: Log water between drinks
- Last 30 days: Recent events on your home screen

**syncTierToSupabase Function:**
```
async syncTierToSupabase(tier: SubscriptionTier, period?: SubscriptionPeriod)
- Called after RevenueCat confirms purchase/restore
- Updates Supabase profiles row with:
  - subscription_tier: tier
  - subscription_period: period ?? null
  - subscription_started_at: tier === 'pro' ? new Date().toISOString() : null
- Fire-and-forget (no error handling)
- Called from RevenueCat purchase listener
```

---

### Calorie Equivalencies (lib/calorie-equivalencies.ts)

**FOOD_EQUIVALENTS Object:**
- Big Mac: 563 kcal
- Pizza slice: 275 kcal
- Glazed donut: 270 kcal
- Chocolate bar: 230 kcal
- Taco: 220 kcal
- Ice cream cone: 200 kcal
- Bag of chips: 155 kcal

**EXERCISE_EQUIVALENTS Object:**
- Running: 700 cal/hr
- Swimming: 500 cal/hr
- Cycling: 550 cal/hr
- Dancing: 400 cal/hr
- Walking: 300 cal/hr
- Yoga: 200 cal/hr

**getFoodComparisons Function:**
```
getFoodComparisons(calories: number) returns {food, count, kcalEach}[]
- For each food item, calculates count = Math.floor(calories / foodKcal)
- Returns foods where count >= 1
- Sorted by count descending
- Used to display "X Big Macs", "Y Pizza slices", etc.
```

**getExerciseComparisons Function:**
```
getExerciseComparisons(calories: number) returns {exercise, minutes, caloriesPerHour}[]
- For each exercise, calculates minutes = Math.round((calories / caloriesPerHour) * 60)
- Returns exercises where minutes >= 5
- Sorted by minutes ascending
- Used to display "30 min running", "45 min walking", etc.
```

**getRelevantFacts Function:**
```
getRelevantFacts(calories: number) returns string[]
- Returns array of 5-10 contextual facts about the calorie amount
- Facts vary based on calorie total (e.g., "equals a Big Mac" vs "equals 2 Big Macs")
- Used for reality-check facts card on summary screen
```

---

### Challenge Utilities (lib/challenge-utils.ts)

**ChallengeProgress Interface:**
- `challenge`: Challenge object
- `current`: number (current progress toward target)
- `target`: number (goal value)
- `percentage`: number (0-100, progress as percentage)
- `isOver`: boolean (true if challenge period ended)
- `daysLeft`: number (days until challenge end)
- `status`: "active" | "completed" | "failed" | "expired"
- `label`: string (human-readable challenge name)

**computeChallengeProgress Function:**
```
computeChallengeProgress(challenge, events, entries, waterEntries) returns ChallengeProgress
- For max_drinks_per_week: counts drinks in 7-day period from start date
- For max_nights_per_month: counts events in calendar month
- For dry_week: checks if any drinks logged in 7-day period (target always 0)
- For max_drinks_per_night: finds max drinks in any single event during period
- For max_calories_per_week: sums calories from all drinks in 7-day period
- Status logic:
  - "active": current period, not completed
  - "completed": target met, period ongoing or ended
  - "failed": period ended, target not met
  - "expired": period ended, cannot be modified
- percentage = (current / target) * 100, clamped 0-100
- daysLeft = Math.max(0, (endDate - now) / (1000 * 60 * 60 * 24))
```

**getDefaultTarget Function:**
```
getDefaultTarget(type: ChallengeType) returns number
- max_drinks_per_week: 10
- max_nights_per_month: 4
- dry_week: 7 (days, fixed, no user input)
- max_drinks_per_night: 4
- max_calories_per_week: 1500
- Used to pre-fill target input in create challenge modal
```

**getEndDate Function:**
```
getEndDate(type: ChallengeType) returns ISO 8601 string
- max_drinks_per_week: 7 days from start date
- max_nights_per_month: last day of month containing start date
- dry_week: 7 days from start date
- max_drinks_per_night: end of same day as start date (or 24 hours)
- max_calories_per_week: 7 days from start date
- Used to calculate daysLeft and determine expiration
```

---

### Analytics and Statistics (lib/analytics.ts)

**AllTimeStats Interface:**
- `totalEvents`: number (count of all events)
- `totalDrinks`: number (sum of all drink quantities)
- `avgDrinksPerNight`: number (totalDrinks / totalEvents)
- `avgMinutesPerDrink`: number (total event duration / totalDrinks)
- `favoriteDrink`: {name: string, count: number} (most frequently logged drink)
- `busiestDay`: string (day of week with most events, e.g., "Friday")
- `recordNight`: {date: string, drinkCount: number} (event with most drinks)
- `weeklyStreak`: number (consecutive weeks with at least one event)
- `weekendStreak`: number (consecutive weekends with events)
- `totalCalories`: number (sum of all drink calories)
- `totalAlcoholG`: number (sum of pure alcohol grams)
- `insights`: string[] (array of generated insight strings)

**MonthlyStats Interface:**
- Same fields as AllTimeStats, but scoped to single calendar month
- Additional fields:
  - `month`: string ("April 2024")
  - `bestNight`: {date: string, drinkCount: number}
  - `worstNight`: {date: string, drinkCount: number}

**computeAllTimeStats Function:**
```
computeAllTimeStats(profile, events, entries, waterEntries) returns AllTimeStats
- Iterates through all events and entries (free tier: last 30 days only)
- Calculates each field above
- generateInsights() produces contextual strings like "You tend to drink more on weekends"
- Used for Dashboard all-time tab
```

**computeMonthlyStats Function:**
```
computeMonthlyStats(profile, year, month, events, entries) returns MonthlyStats
- Filters events to specified year/month only
- Similar calculations as all-time, month-scoped
- Used for Dashboard monthly tab and Calendar month view
```

**Helper Functions:**
- `computeFavoriteDrink(entries)`: groups by drink type, returns most frequent
- `computeBusiestDay(events)`: groups by day of week, returns day with most events
- `computeAvgMinutesPerDrink(events, entries)`: total duration / total drinks
- `computeWeeklyStreak(events)`: counts consecutive weeks with at least 1 event
- `computeWeekendStreak(events)`: counts consecutive Fri-Sat-Sun periods with events

---

## Part 3: Design Language and Visual System

### Color Palette (constants/colors.ts)

**Dark Mode (Primary Theme):**
- `background`: #0A0A0F (page background, darkest)
- `surface`: #141420 (card/component background)
- `surfaceElevated`: #1C1C2E (elevated cards, modals)
- `border`: #2A2A3A (subtle borders)
- `text`: #F5F5F7 (primary text, white-ish)
- `textSecondary`: #8E8E9A (secondary text, muted)
- `textTertiary`: #5A5A6A (tertiary text, dimmer)

**Accent Colors:**
- `accent`: #F0A830 (primary action, highlights, orange)
- `accentDim`: rgba(240, 168, 48, 0.15) (15% opacity accent, backgrounds)
- `accentGlow`: rgba(240, 168, 48, 0.3) (30% opacity accent, borders/glows)

**Status Colors:**
- `success`: #2ED573 (green, positive states)
- `successDim`: rgba(46, 213, 115, 0.15) (15% opacity green)
- `danger`: #FF4757 (red, warnings/errors)
- `dangerDim`: rgba(255, 71, 87, 0.15) (15% opacity red)

### Typography

**Font Family:** Inter (all weights)

**Font Sizes and Weights Used:**
- 10px: secondary/tertiary labels, hints, disclaimers (400 Regular)
- 11px: chip labels, fine print, metadata (400 Regular)
- 12px: section titles, input labels, secondary content (500 Medium)
- 13px: tertiary timestamps, subtext (400 Regular)
- 14px: primary body text, card content, input text (400 Regular)
- 15px: button text, emphasis (600 SemiBold)
- 16px: screen titles, emphasis headers (600 SemiBold)
- 18px: modal titles (600 SemiBold)
- 24px: hero titles, event names (700 Bold, sometimes letter-spacing -0.3)
- 28px: stat values, large metrics (700 Bold)
- 44px: hero stat displays (700 Bold)

### Spacing System

**Standard Gap Values:**
- 4px: tight spacing (icon-to-label, small lists)
- 6px: extra-small gap
- 8px: small gap (between chips, grid items)
- 12px: medium gap (section padding, input gaps)
- 16px: standard gap (card padding, section margins)
- 20px: large gap (header spacing)
- 24px: extra-large gap (screen margins)
- 32px: hero spacing (empty state margins)

### Border Radius

- 0px: none (rarely used)
- 4px: small radius (icons, small components)
- 8px: standard radius (buttons, input fields, small cards)
- 12px: large radius (card components, modals)
- 50% (circle): avatars, round buttons

### Border Styling

- 1px `border` color (#2A2A3A): standard borders on cards, inputs
- 1px `secondary` color (#8E8E9A): alternative borders
- 2px `accent` color (#F0A830): active/selected states
- 2px `accentGlow`: prominent borders (pro cards, hero modals)
- No border (transparent): some button states

### Shadows

- No drop shadows (dark mode, flat design aesthetic)
- Uses borders and background color modulation instead
- accentGlow borders provide elevation effect on key cards

### Button Variants

**Accent (Primary):**
- Background: #F0A830
- Text: white
- Height: 44-48px
- Border-radius: 8px
- Font: 14-15px, bold
- Icon (if present): 16-20px, white, right-aligned
- State changes: opacity 0.8 on press (no explicit disabled state shown)

**Secondary (Alternative):**
- Background: surface (#141420) or transparent
- Border: 1px secondary (#8E8E9A)
- Text: secondary (#8E8E9A)
- Height: 44px
- Border-radius: 8px
- Font: 14px, regular or semibold

**Danger (Destructive):**
- Background: dangerDim (rgba(255, 71, 87, 0.15))
- Border: 1px danger (#FF4757)
- Text: danger (#FF4757)
- Height: 44-48px
- Border-radius: 8px
- Icon: trash-bin-outline, alert-circle-outline, 16-20px

### Card Patterns

**Standard Card:**
- Background: surface (#141420)
- Border: 1px border (#2A2A3A)
- Padding: 12-16px
- Border-radius: 8-12px
- No shadow (flat design)

**Elevated Card (Hero/Modal):**
- Background: surfaceElevated (#1C1C2E)
- Border: 1px border (#2A2A3A)
- Padding: 16px
- Border-radius: 12px

**Accent/Highlight Card:**
- Background: accentDim (15% opacity orange)
- Border: 1-2px accentGlow (30% opacity orange)
- Padding: 12-16px
- Border-radius: 8-12px

**Danger Card:**
- Background: dangerDim (15% opacity red)
- Border: 1px danger (#FF4757)
- Text: danger (#FF4757)
- Padding: 12px
- Border-radius: 8px

### Animations

**FadeInDown:**
- Duration: 200ms
- Direction: top to bottom with opacity fade
- Used for: undo bar, water nudge, alerts
- Easing: ease-out

**FadeOutDown:**
- Duration: 200ms
- Direction: bottom (fade out while moving down slightly)
- Used for: auto-dismiss animations
- Easing: ease-in

**Pulse Animation (on LIVE badge):**
- Duration: 1.5 seconds
- Effect: opacity 0.6 → 1.0 → 0.6, repeat infinite
- Used for: active event indicator
- Easing: ease-in-out

**Scale/Bounce (on button press):**
- Duration: 100-150ms
- Effect: scale 1.0 → 0.95 → 1.0
- Used for: all interactive elements
- Easing: ease-out (bounce)

### Haptic Feedback Patterns

**Light Haptic:**
- Used for: toggle switches, non-critical taps
- Pattern: short, subtle vibration

**Medium Haptic:**
- Used for: button presses, form submissions
- Pattern: standard notification vibration

**Heavy Haptic:**
- Used for: drink additions, major actions
- Pattern: strong vibration (3-4x medium intensity)

**Selection Haptic:**
- Used for: picker selections, date changes
- Pattern: light tick-like vibration

**Success Haptic:**
- Used for: event creation, save confirmations
- Pattern: double-tap vibration pattern

**Warning Haptic:**
- Used for: BAC limit exceeded, driving mode alerts
- Pattern: repeating short vibrations

**Error Haptic:**
- Used for: validation failures, delete actions
- Pattern: triple-tap sharp vibration

---

## Part 4: Storage and Synchronization

### AsyncStorage Keys (Local Client-Side Storage)

**Prefix Convention:** All keys use `noche_` prefix (named after "noche" context system)

**Key Mappings:**
- `noche_events`: serialized array of NightEvent objects
- `noche_entries`: serialized array of DrinkEntry objects
- `noche_water_entries`: serialized array of WaterEntry objects
- `noche_drinks`: serialized array of DrinkType objects (custom + preset)
- `noche_profile`: serialized UserProfile object
- `noche_challenges`: serialized array of Challenge objects
- `noche_active_event_id`: current active event ID (string or null)
- `noche_sync_timestamp`: last successful Supabase sync timestamp
- `noche_onboarding_complete`: boolean flag for onboarding state

**Sync Strategy:**
- Local-first: all mutations happen in AsyncStorage immediately
- Periodic sync to Supabase in background (every 5-10 seconds if changes detected)
- Offline-capable: full app functionality without network
- Conflict resolution: last-write-wins with timestamp comparison

### Supabase Tables and Schema

**profiles Table:**
- `id`: UUID primary key (matches auth.users.id)
- `sex`: enum ('male', 'female', 'prefer_not_to_say')
- `weight_kg`: integer (35-200)
- `height_cm`: integer | null
- `birth_year`: integer | null
- `bac_limit`: float (default 0.08)
- `water_suggestions_enabled`: boolean (default true)
- `notifications_enabled`: boolean (default false)
- `drinks_per_hour_limit`: integer (default 4, 1-20)
- `calories_per_night_goal`: integer (default 2000)
- `bac_approach_warning`: boolean (default true)
- `stage_change_warning`: boolean (default true)
- `disclaimer_accepted_at`: timestamp | null
- `device_id`: string
- `onboarding_complete`: boolean (default false)
- `subscription_tier`: enum ('free', 'pro') (default 'free')
- `subscription_period`: enum ('monthly', 'yearly', 'lifetime') | null
- `subscription_started_at`: timestamp | null
- `updated_at`: timestamp (auto-updated)

**night_events Table:**
- `id`: UUID primary key
- `user_id`: UUID foreign key → profiles(id)
- `name`: string (event title)
- `start_time`: timestamp
- `end_time`: timestamp | null
- `created_at`: timestamp
- `driving_mode`: boolean (default false)
- `bac_limit`: float | null
- `notes`: text | null

**drink_entries Table:**
- `id`: UUID primary key
- `event_id`: UUID foreign key → night_events(id)
- `drink_type_id`: UUID foreign key → drink_types(id)
- `timestamp`: timestamp
- `quantity`: integer (default 1)
- `comment`: text | null
- `volume_override_ml`: integer | null
- `abv_override`: float | null

**water_entries Table:**
- `id`: UUID primary key
- `event_id`: UUID foreign key → night_events(id)
- `timestamp`: timestamp
- `volume_ml`: integer (default 250)

**drink_types Table:**
- `id`: UUID primary key
- `name`: string
- `default_volume_ml`: integer
- `default_abv`: float
- `calories_per_serving`: integer
- `is_preset`: boolean (true for hardcoded 16 drinks)
- `icon`: string (icon key)
- `user_id`: UUID foreign key | null (null for preset drinks)
- `created_at`: timestamp

**challenges Table:**
- `id`: UUID primary key
- `user_id`: UUID foreign key → profiles(id)
- `type`: enum ('max_drinks_per_week', 'max_nights_per_month', 'dry_week', 'max_drinks_per_night', 'max_calories_per_week')
- `target`: integer (goal value, 0 for dry_week)
- `start_date`: timestamp
- `end_date`: timestamp
- `created_at`: timestamp
- `completed`: boolean (default false)

### RevenueCat Integration

**Purchase Flow:**
1. User taps "Subscribe" button on pricing screen
2. App initiates RevenueCat purchase dialog
3. RevenueCat handles payment processing through App Store / Google Play
4. On successful purchase, RevenueCat calls purchaseListener callback
5. Callback extracts subscription tier and period
6. App calls syncTierToSupabase(tier, period) to update profiles table
7. App updates local profile in context/AsyncStorage
8. UI updates to show pro badge and unlock pro features

**RevenueCat Events:**
- `purchasesUpdated`: fires on purchase, restore, or cancellation
- Entitlements available: "pro" (premium features access)
- Customer info: subscription status, expiration date, auto-renewal status

**Restore Purchases:**
- User taps "Restore purchases" on pricing screen
- App calls RevenueCat.restorePurchases()
- RevenueCat returns previous purchase entitlements
- App calls syncTierToSupabase() to sync to Supabase
- UI updates to reflect restored subscription

---

## Part 5: Feature Gating (Free vs Pro Tier)

### Free Tier Features (Always Available)

1. **Track nights:** Create events, log drinks with preset drink types (16 options), view live BAC during event
2. **Driving mode:** Enable in create-event, set BAC limit (0.05% or 0.08%), receive warnings if BAC exceeds limit
3. **Default drinks:** Access 16 preset drinks (Beer, Wine, Spirits, Cocktails, Hard Seltzer, Michelada)
4. **Hydration tracking:** Log water intake during events, receive water nudges
5. **Last 30 days:** View recent events on home screen and summary history (limited to 30 days of data, pro gets unlimited)
6. **Event summary:** View detailed breakdown, BAC metrics, notes for completed events (no calorie equivalencies)

### Pro Tier Features (Paid Only)

1. **Extended history:** See every past night, not just the last 30 days (unlimited historical data access)
2. **Calendar view:** Monthly overview with intensity heatmap, day-by-day breakdown, event details
3. **Dashboard/Stats & trends:** All-time statistics, monthly statistics, favorite drink, busiest day, record night, streaks, insights
4. **Challenges:** Create and track 5 challenge types (max drinks/week, max nights/month, dry week, max drinks/night, max calories/week)
5. **Custom drinks:** Edit preset drinks, create custom drink types with custom icon, volume, ABV, calories
6. **Calorie equivalencies:** Food comparisons (Big Mac, pizza, etc.), exercise comparisons (running, swimming, etc.), reality facts

### Feature Gating Implementation

**Paywall Component (components/Paywall.tsx):**
- Displayed as overlay when accessing pro feature without active subscription
- Shows icon, title, description, "Unlock with Pro" CTA, pricing, "See all plans" link
- Used for: Calendar, Dashboard, Challenges, Drinks edit, Calorie equivalencies

**Navigation Guards:**
- Routes to pro screens check `isPro(profile)` before rendering
- If not pro and not authenticated, shows paywall
- If authenticated but not pro, shows paywall
- If pro, renders full screen

**Data Filtering:**
- Free tier: events filtered to last 30 days on data fetch
- Pro tier: all historical data available
- Free tier: calorie data suppressed on summary screen
- Pro tier: calorie section fully visible with equivalencies

---

## Part 6: Validation Rules and Input Constraints

### User Profile Inputs

**Sex:**
- Required field
- 3 options: "Male", "Female", "Prefer not to say"
- No free-form input

**Weight (kg):**
- Required field
- Type: numeric
- Min: 35 kg
- Max: 200 kg
- Max characters: 3
- Validation: must be integer, must be within range
- Error message: "Enter weight between 35–200 kg"

**Height (cm):**
- Optional field
- Type: numeric
- Min: 100 cm
- Max: 230 cm
- Max characters: 3
- Validation: if provided, must be within range
- No error display if empty (optional)

**Birth Year:**
- Optional field
- Type: numeric
- Min: 1900
- Max: current year
- Max characters: 4
- Validation: if provided, must be within range and be valid year
- No error display if empty (optional)

**Drinks Per Hour Limit:**
- Nested under notifications toggle (editable only if enabled)
- Type: numeric
- Min: 1 drink/hour
- Max: 20 drinks/hour
- Default: 4
- Used for pace warning threshold

**Calorie Budget Per Night:**
- Nested under notifications toggle (editable only if enabled)
- Type: numeric
- Min: 500 kcal
- Max: 5000 kcal
- Default: 2000
- Used for calorie warning threshold

**BAC Limit (Driving Mode):**
- Two preset options: "0.05% Conservative" or "0.08% Standard"
- No free-form input
- Default: 0.08%
- Stored in event record

### Event Creation Inputs

**Event Name:**
- Type: text
- Max length: 100 characters
- Placeholder: "e.g. Friday with friends"
- Required field
- No validation beyond max length

**Event Date:**
- Type: date picker
- Default: today
- Min: any past date
- Max: today (cannot create events in future)
- Format: "MMM DD" (e.g., "Apr 26")

**Event Time:**
- Type: time picker
- Format: "HH:MM AM/PM" (e.g., "8:30 PM")
- Default: current time
- No validation (any 24-hour time allowed)

### Drink Entry Inputs

**Quantity:**
- Type: numeric stepper
- Min: 1
- Max: 99
- Default: 1
- Increments by 1
- Display: centered, bold, accent color

**Comment:**
- Type: text
- Max length: 200 characters
- Placeholder: "e.g. felt strong"
- Optional field
- Multiline: no line limit

### Custom Drink Inputs (Pro-Gated)

**Drink Name:**
- Type: text (Inter 400 Regular 16px)
- Max length: 30 characters
- Placeholder: none
- Required field
- Label: "NAME" (all-caps)

**Volume (ml):**
- Type: numeric
- Min: 1 ml
- Max: 1000 ml
- Default: preset value (e.g., 355 for beer)
- Placeholder: "e.g. 355"
- Label: "ML" (all-caps)
- Unit: "ml" displayed right of input

**ABV Percentage:**
- Type: numeric (decimal)
- Min: 0.0%
- Max: 95% (or physically realistic max ~60%)
- Default: preset value (e.g., 5.0 for beer)
- Placeholder: "e.g. 5.0"
- Label: "ABV %" (all-caps)
- Unit: "%" displayed right of input
- Decimal precision: 1 place (5.0, not 5.00)

**Calories per Serving:**
- Type: numeric
- Min: 0 kcal
- Max: 500 kcal
- Default: preset value (e.g., 153 for beer)
- Placeholder: "e.g. 153"
- Label: "KCAL" (all-caps)
- Unit: "kcal" displayed right of input

**Icon Selection:**
- Type: picker (16 icon options in horizontal scroll)
- Options: beer, wine-bottle, shot-glass, champagne, cocktail, etc.
- Display: 48×48 circles, selected=accentDim+accent border
- Required field

### Date and Time Formatting

**Date Display Formats:**
- Home screen event list: "MMM DD" (e.g., "Apr 26")
- Summary hero: "dddd, MMMM DD, YYYY" (e.g., "Friday, April 26, 2024")
- Calendar day cell: "DD" (e.g., "26")
- Stats screens: "MMM DD, YYYY" or "MMM DD"
- Profile saved date: "MMM DD, YYYY" (e.g., "Apr 26, 2024")

**Time Display Formats:**
- Event header: "HH:MM AM/PM" (e.g., "8:30 PM")
- Duration: "Xm" for minutes (e.g., "45m"), "Xh XXm" for hours+minutes (e.g., "2h 15m")
- Timeline timestamp: "H:MM AM/PM" (12-hour with leading zero on hours)
- Intoxication bar labels: "0.0%", "0.5%" (with decimal)

### Number Formatting Rules

**Decimal Precision:**
- BAC: 2-3 decimal places (0.08%, 0.125%, 0.050%)
- Alcohol grams: 1 decimal place (12.3g)
- Standard drinks: 1 decimal place (1.5 drinks)
- Calories: integer, no decimals (153 kcal)
- ABV: 1 decimal place (5.0%)
- Volume: integer, no decimals (355 ml)

**Number Separators:**
- Thousands separator: comma (e.g., 1,500 kcal)
- Decimal separator: period (e.g., 0.08%)
- No locale-specific formatting override (always use US format)

### Intoxication Stage Ranges (Strict Boundaries)

- Sober: 0.00% - 0.02%
- Buzzed: 0.02% - 0.05% (exclusive lower, inclusive upper)
- Tipsy: 0.05% - 0.08%
- Impaired: 0.08% - 0.15%
- Drunk: 0.15% - 0.25%
- Very drunk: 0.25% - 0.35%
- Danger: 0.35% - 0.50%+

---

## Part 7: Empty and Loading States

### Empty State: No Events

**Home Screen:**
- Icon: sparkles-outline (48px, secondary text color)
- Title: "No nights yet" (16px, semibold)
- Subtitle: "Start a night to begin tracking" (14px, secondary)
- Button: "Start my first night" (accent background, full width)
- Centered, with 32px bottom margin

### Empty State: No Challenges

**Challenges Screen:**
- Icon: trophy-outline (48px, secondary)
- Title: "No challenges yet" (16px, bold)
- Subtext: "Set a goal to get started" (12px, secondary)
- Button: "Create challenge" (accent background, arrow-forward icon)

### Empty State: Calendar Day (No Event Selected)

**Calendar Screen:**
- Icon: hand-left-outline (48px, secondary)
- Text: "Tap a day with activity to see details" (14px, secondary)
- Centered, no button

### Loading States

**Event Summary Loading:**
- Skeleton loader with animated shimmer effect
- Hero card placeholder (12px height line, repeated 3 times)
- Stats row placeholder (4 cards, gradient shimmer)
- Breakdown section (5 placeholder bars)
- Duration: appears for 200-500ms during data fetch

**Purchase Loading:**
- "Restore purchases" button shows ActivityIndicator replacing text
- Button becomes disabled during load
- Button re-enables after 2-3 seconds or on error

**Delete Account Loading:**
- "Delete my account" button shows ActivityIndicator replacing text
- Button becomes disabled, user cannot cancel operation
- After deletion, navigates to auth screen

**Event Creation Loading:**
- "Start night" button shows ActivityIndicator replacing icon+text
- Button disabled during creation
- Modal backdrop semi-transparent (darker than normal)
- Re-enables after success or shows error toast

### Error States

**Weight Validation Error:**
- Input border: 2px red (#FF4757)
- Input background: 10% red opacity
- Error message below input: "Enter weight between 35–200 kg" (11px, red)
- Message displays immediately on blur or when user tries to save

**Network Error:**
- Toast notification: "Network error. Changes will sync when online." (12px, secondary, 4-second duration)
- User can continue using app (offline-capable)
- Sync retries automatically when connection restored

**Purchase Error:**
- Modal: "Purchase failed" (16px, bold)
- Message: error text from RevenueCat (12px, secondary)
- Button: "Try again" (accent background)
- Dismiss option: X button or overlay tap

---

## Part 8: Storage Key Constants and Prefixes

### AsyncStorage Noche Prefix Keys

All stored data uses the prefix `noche_` for scoping and organization.

**Complete Key List:**
- `noche_events`: JSON array of NightEvent objects
- `noche_entries`: JSON array of DrinkEntry objects
- `noche_water_entries`: JSON array of WaterEntry objects
- `noche_drinks`: JSON array of DrinkType objects
- `noche_profile`: JSON object of UserProfile
- `noche_challenges`: JSON array of Challenge objects
- `noche_active_event_id`: string | null (UUID of currently active event)
- `noche_sync_timestamp`: ISO 8601 timestamp of last successful Supabase sync
- `noche_onboarding_complete`: boolean flag

**Usage Pattern:**
```
await AsyncStorage.getItem('noche_events').then(JSON.parse)
await AsyncStorage.setItem('noche_events', JSON.stringify(updatedEvents))
```

---

## Part 9: Implementation Notes and Disclaimers

### Calculation Disclaimers

All BAC and alcohol calculations are estimates based on scientific formulas (Widmark and Watson) and do NOT account for individual metabolic variations, food intake, medication interactions, or other factors. Results may differ significantly from actual blood alcohol content. Always use a designated driver, never drive after drinking, and seek professional medical advice for alcohol-related health concerns.

### Privacy and Data Handling

User profile data (sex, weight, height, birth year) is stored locally on device and in Supabase. No data is shared with third parties except for RevenueCat (subscription management only). Users can delete their account and all associated data through the delete account button.

### Attribution

- BAC formulas based on Widmark (1932) and Watson et al. (1981) research
- Alcohol standard drink definition (14g pure alcohol per drink) follows US regulatory standard
- Calorie data sourced from USDA FoodData Central
- Exercise calorie burn estimates based on MET (Metabolic Equivalent) research

### Known Limitations

- Free tier limited to 30 days of history (to reduce storage and improve performance)
- Peak BAC calculation assumes instant drink consumption (not realistic for hours-long events)
- Hydration impact capped at 5% BAC reduction (conservative estimate, water does not speed metabolism)
- Calendar intensity only accounts for drink quantity, not alcohol percentage or calorie content
- Challenge progress calculated at point-in-time (not real-time as event continues)

### Future Enhancement Ideas (Out of Scope for This Spec)

- Integration with wearable devices for real BAC estimation
- Social features (share events, compare stats with friends)
- AI-powered insights and personalized recommendations
- Integration with Uber/Lyft for designated driver booking
- Machine learning model to predict BAC more accurately based on user history

---

**END OF SPECIFICATION**

**Line Count:** This specification contains approximately 1,400+ lines covering all screens, data types, algorithms, design language, storage, feature gating, validation rules, and implementation details needed to rebuild the SipTrack (Tracksip) app from scratch.