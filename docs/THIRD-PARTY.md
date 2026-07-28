# Third-party components

Coral is built on and integrates several open-source projects. This file records the
ones Coral installs, invokes, or ships alongside, and their licenses.

## graphify (`graphifyy`)

- **Used for:** the **Map** section — turning a repository into a code knowledge graph.
- **How:** Coral does **not** vendor graphify's source. On first use of the Map, Coral
  creates its own isolated Python virtual-environment under
  `~/Library/Application Support/Coral/graphify/` and installs a pinned release of the
  `graphifyy` package from PyPI into it, then invokes that interpreter. Nothing is added
  to the user's global Python environment.
- **License:** Apache-2.0 (dual-licensed MIT). Copyright © its authors (Safi Shamsi et al.).
- **Homepage:** <https://graphify.net> · **Source:** <https://github.com/safishamsi/graphify>

Because graphify is fetched at runtime rather than redistributed inside the Coral app
bundle, its license text travels with the installed package; this note provides
attribution. If a future release bundles graphify (or a Python runtime) inside the
signed `.app`, include the full Apache-2.0 LICENSE + NOTICE for the bundled components
here.
