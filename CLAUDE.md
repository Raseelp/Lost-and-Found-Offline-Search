# Notes for Claude

## Documentation

- README.md stays short: one line per feature, no explanation of how it works. Do not add
  sections or paragraphs to the README for a new feature.
- Feature details and how things work go in `docs/`: `architecture.md` (models, pipelines,
  storage), `people.md`, `memories.md`, `export.md`, `development.md`. Add to the matching file,
  or a new file in `docs/` linked from the README.
- Every user-visible change gets a line in CHANGELOG.md under "Unreleased" (Added, Changed, Fixed
  or Removed).
- When a change makes something in README.md or `docs/` wrong, fix it in the same commit.
- Style: plain short sentences, no marketing words, no emoji, no em dashes, no bullets that start
  with a bolded phrase.
