---
title: macOS Utility Design Guide
version: 1.0
status: guidance
scope: focused macOS utility apps
---

# macOS Utility Design Guide

Default for small, single-purpose macOS tools. Priority: explicit requirements → native macOS conventions → usability and accessibility → this guide. When unspecified, choose the simplest native solution.

## 1. Principles

- Focus on one primary task.
- Feel quiet, direct, and native.
- Keep the interface proportional to the task; avoid dashboard patterns.
- Reveal advanced options only when needed.
- Do not invent features, content, or decoration.

## 2. Structure

- Prefer one main window and one primary workflow.
- Preserve native title bars, traffic lights, menus, dialogs, and window behavior.
- Keep task states in one stable content region.
- Use toolbars, status areas, sheets, and Settings only when necessary.
- Support default and minimum window sizes without hiding essential actions.
- Avoid sidebars, tabs, cards, and multi-page navigation unless required.

## 3. Interaction

- Make the flow clear: input → action → result.
- Present one primary action and avoid duplicate controls.
- Pair drag and drop with a keyboard-accessible picker or menu command.
- Prefer native file pickers and Finder integration.
- Make destructive, cancel, stop, retry, reset, and overwrite behavior explicit.
- Disable unsafe actions while work is running.
- Preserve input after recoverable errors.

## 4. States

- Handle relevant empty, ready, working, success, and failure states.
- Show real activity or progress; never fake precision.
- Keep errors actionable and preserve a recovery path.
- Never communicate state through color, sound, or animation alone.

## 5. Visuals

- Prefer system controls, fonts, SF Symbols, and semantic colors.
- Build hierarchy with spacing, type, alignment, and subtle separators.
- Support Light, Dark, Increase Contrast, Reduce Transparency, and Reduce Motion.
- Use materials and animation sparingly and functionally.
- Avoid ornamental effects and custom imitations of system controls.

## 6. Copy and accessibility

- Keep labels short, concrete, consistent, and stated once.
- Preserve real filenames, paths, formats, and system names.
- Do not add unverified marketing, privacy, or technical claims.
- Provide a keyboard path for every essential action.
- Give icon-only controls accessible names and help text.
- Keep focus order predictable; do not hide essential actions behind hover.

## 7. Agent check

- Is the primary task obvious?
- Are all relevant states handled?
- Do default/minimum sizes and Light/Dark appearances work?
- Are applicable keyboard, VoiceOver, drag-and-drop, and Finder flows usable?
- Are destructive actions safe and errors recoverable?
- Is every control, label, state, and decoration necessary?
