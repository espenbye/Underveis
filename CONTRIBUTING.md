# Contributing

Underveis is a solo side project. Issues and pull requests are welcome, but reviews may be slow.

- Work happens directly on `main`; use [Conventional Commits](https://www.conventionalcommits.org).
- Build both platforms before opening a PR (`make build`); the tree must be warning-clean under
  Swift 6 strict concurrency.
- Edit `project.yml`, never `Underveis.xcodeproj` by hand, and commit the regenerated project.
- See the README for the architecture and `CONTEXT.md` for the Norwegian UI vocabulary.
