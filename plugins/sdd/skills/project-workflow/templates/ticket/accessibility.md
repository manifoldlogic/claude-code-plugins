# Accessibility Review: {NAME}

## Overview

[High-level description of the accessibility considerations for this ticket. What UI components or user interactions are being added or modified? Who are the users that benefit from accessibility improvements?]

**Target Compliance Level:** [WCAG 2.1 Level A / AA / AAA]
**Component Type:** [Form / Navigation / Modal / Page / Widget / Other]
**User Impact:** [Which users are most affected by accessibility of this feature?]

## WCAG Compliance

[Which WCAG success criteria are relevant to this ticket? Focus on criteria that apply to the specific UI changes being made.]

### Level A (Minimum)

[These criteria MUST be met for basic accessibility.]

- [ ] **1.1.1 Non-text Content** -- All images, icons, and non-text elements have text alternatives
  - [Describe approach: e.g., alt text on images, aria-label on icon buttons]
- [ ] **1.3.1 Info and Relationships** -- Structure and relationships conveyed visually are also available programmatically
  - [e.g., Proper heading hierarchy, form labels associated with inputs, table headers marked up correctly]
- [ ] **1.3.2 Meaningful Sequence** -- Reading order matches visual order
  - [e.g., DOM order reflects logical content flow]
- [ ] **2.1.1 Keyboard** -- All functionality available via keyboard
  - [e.g., All interactive elements reachable and operable with Tab, Enter, Space, Arrow keys]
- [ ] **2.4.1 Bypass Blocks** -- Skip navigation mechanism available
  - [e.g., Skip-to-main-content link, proper landmark regions]
- [ ] **4.1.1 Parsing** -- Valid, well-formed markup
- [ ] **4.1.2 Name, Role, Value** -- All UI components have accessible name, role, and state
  - [e.g., Custom components use appropriate ARIA roles and properties]

### Level AA (Standard)

[These criteria SHOULD be met for a good accessibility experience.]

- [ ] **1.4.3 Contrast (Minimum)** -- Text has at least 4.5:1 contrast ratio (3:1 for large text)
  - [Describe contrast verification approach]
- [ ] **1.4.4 Resize Text** -- Text can be resized to 200% without loss of content or functionality
- [ ] **1.4.11 Non-text Contrast** -- UI components and graphics have at least 3:1 contrast ratio
- [ ] **2.4.6 Headings and Labels** -- Headings and labels describe topic or purpose
- [ ] **2.4.7 Focus Visible** -- Keyboard focus indicator is visible
  - [Describe focus indicator style]
- [ ] **3.2.3 Consistent Navigation** -- Navigation consistent across pages
- [ ] **3.3.1 Error Identification** -- Input errors clearly identified and described in text
- [ ] **3.3.2 Labels or Instructions** -- Labels or instructions provided for user input

### Additional Criteria (if applicable)

[List any Level AAA criteria or additional standards being targeted.]

- [ ] [Criterion]: [How it applies]

## Keyboard Navigation

[Detailed keyboard interaction specification. Every interactive element must be operable without a mouse.]

### Tab Order

[Describe the expected tab order through the UI. Tab order should follow logical reading flow.]

1. [First focusable element]
2. [Second focusable element]
3. [Continue in logical order...]

### Keyboard Shortcuts

| Key | Action | Context |
|-----|--------|---------|
| `Tab` | [Move to next focusable element] | [Global] |
| `Shift+Tab` | [Move to previous focusable element] | [Global] |
| `Enter` / `Space` | [Activate button or link] | [When focused on interactive element] |
| `Escape` | [Close modal / dismiss popover] | [When modal or popover is open] |
| `Arrow keys` | [Navigate within component] | [e.g., Within menu, tab list, radio group] |
| [Custom shortcut] | [Action] | [Context] |

### Focus Management

[How focus is managed during dynamic content changes.]

- **Modal open:** [Focus moves to first focusable element in modal, trapped within modal]
- **Modal close:** [Focus returns to triggering element]
- **Dynamic content:** [e.g., When content loads, focus moves to new content or announcement is made]
- **Delete/remove action:** [Focus moves to logical next element after removed item]
- **Error state:** [Focus moves to first error or error summary]

### Focus Trap Boundaries

[Where focus must be contained (modals, dialogs, dropdown menus).]

- [Component]: [Focus trap behavior]

## Screen Readers

[How the UI communicates to screen reader users.]

### ARIA Landmarks

[Define the landmark regions for the page/component.]

| Landmark | Element | Label |
|----------|---------|-------|
| `banner` | `<header>` | [Page header] |
| `navigation` | `<nav>` | [e.g., "Main navigation", "Breadcrumbs"] |
| `main` | `<main>` | [Primary content area] |
| `complementary` | `<aside>` | [e.g., "Sidebar", "Related content"] |
| `contentinfo` | `<footer>` | [Page footer] |

### ARIA Attributes

[Key ARIA attributes used in this feature.]

| Element | Attribute | Value | Purpose |
|---------|-----------|-------|---------|
| [e.g., Search input] | `aria-label` | [e.g., "Search tickets"] | [Provides accessible name] |
| [e.g., Loading spinner] | `aria-live` | [e.g., "polite"] | [Announces dynamic content] |
| [e.g., Accordion] | `aria-expanded` | [e.g., "true/false"] | [Communicates open/closed state] |
| [e.g., Tab panel] | `aria-controls` | [e.g., "panel-1"] | [Associates tab with panel] |
| [e.g., Error message] | `role` | [e.g., "alert"] | [Announces error immediately] |

### Live Regions

[How dynamic content changes are announced to screen readers.]

- **Status updates:** [e.g., `aria-live="polite"` on status message area]
- **Error messages:** [e.g., `role="alert"` for form validation errors]
- **Progress indicators:** [e.g., `aria-live="polite"` with percentage updates]
- **Toast notifications:** [e.g., `role="status"` for non-critical, `role="alert"` for critical]

### Screen Reader Testing

[Which screen readers will be used for testing?]

- [ ] VoiceOver (macOS / iOS)
- [ ] NVDA (Windows)
- [ ] JAWS (Windows)
- [ ] TalkBack (Android)

## Visual Design

[Accessibility considerations in the visual design.]

### Color Contrast

| Element | Foreground | Background | Ratio | Passes |
|---------|-----------|------------|-------|--------|
| [Body text] | [e.g., #333333] | [e.g., #FFFFFF] | [e.g., 12.6:1] | [AA/AAA] |
| [Link text] | [e.g., #0066CC] | [e.g., #FFFFFF] | [e.g., 5.9:1] | [AA] |
| [Button text] | [e.g., #FFFFFF] | [e.g., #0052A3] | [e.g., 7.1:1] | [AA/AAA] |
| [Error text] | [e.g., #CC0000] | [e.g., #FFFFFF] | [e.g., 5.6:1] | [AA] |
| [Placeholder] | [e.g., #767676] | [e.g., #FFFFFF] | [e.g., 4.5:1] | [AA] |

### Color Independence

- [ ] Information is not conveyed by color alone (e.g., error states use icon + color + text)
- [ ] Links distinguishable from body text by more than color (e.g., underline)
- [ ] Charts and graphs use patterns or labels in addition to color
- [ ] Form validation uses text messages, not just red borders

### Motion and Animation

- [ ] Animations respect `prefers-reduced-motion` media query
- [ ] No content flashes more than 3 times per second
- [ ] Auto-playing content can be paused, stopped, or hidden
- [ ] Transitions are subtle and purposeful (under 300ms recommended)

### Responsive Design

- [ ] Content reflows at 320px viewport width (no horizontal scrolling)
- [ ] Touch targets are at least 44x44 CSS pixels
- [ ] Text can be resized to 200% without content overflow
- [ ] Spacing adapts appropriately at all breakpoints

## Testing

[How accessibility will be verified.]

### Automated Testing

- [ ] axe-core or similar tool integrated into test suite
- [ ] Linting rules for common accessibility issues (e.g., eslint-plugin-jsx-a11y)
- [ ] CI pipeline includes accessibility checks

### Manual Testing

- [ ] Keyboard-only navigation tested (unplug mouse, navigate entire feature)
- [ ] Screen reader walkthrough completed
- [ ] Color contrast verified with tool (e.g., Colour Contrast Analyser)
- [ ] Zoom to 200% tested
- [ ] Reduced motion preference tested

### Test Cases

| Scenario | Expected Behavior | Pass/Fail |
|----------|-------------------|-----------|
| [Tab through all interactive elements] | [Focus order is logical, all elements reachable] | [ ] |
| [Activate button with Enter key] | [Button action triggered] | [ ] |
| [Open modal with keyboard] | [Focus trapped in modal, Escape closes] | [ ] |
| [Submit form with errors] | [Errors announced, focus moves to first error] | [ ] |
| [Navigate with screen reader] | [All content and state announced correctly] | [ ] |
| [View at 200% zoom] | [No content loss, no horizontal scroll] | [ ] |

## Accessibility Checklist

- [ ] All images have appropriate alt text
- [ ] Form inputs have associated labels
- [ ] Color contrast meets WCAG AA requirements
- [ ] All functionality available via keyboard
- [ ] Focus order is logical
- [ ] Focus indicators are visible
- [ ] ARIA attributes used correctly (prefer semantic HTML first)
- [ ] Dynamic content changes announced to screen readers
- [ ] Error messages are descriptive and associated with inputs
- [ ] Page has proper heading hierarchy
- [ ] Landmark regions defined
- [ ] Reduced motion preference respected

## N/A Sign-Off (If Not Applicable)

If this document is not applicable to the current ticket, complete this section instead:

**Status:** N/A
**Assessed:** {date}

### Assessment
{1-3 sentence justification}

### Re-evaluate If
{Condition that would make this document applicable}
