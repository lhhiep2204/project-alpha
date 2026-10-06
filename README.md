# ProjectAlpha

An independent local-first place collection app. The current implementation target is iPhone and iPad on iOS/iPadOS 27, using SwiftUI, SwiftData and Clean Architecture. Its target UI follows Apple's Human Interface Guidelines with native, resizable presentations for iPhone, iPad and iPhone Duo rather than device-specific screen assumptions.

Fast launch and interaction, smooth UI, and lightweight installation are high-priority product requirements. The [implementation and verification plan](docs/08-implementation-and-verification.md) defines how to measure them; the documentation does not claim they have been achieved.

Start with the [design specification](docs/README.md) before implementing features. It contains confirmed product decisions, screen flows, architecture, data rules, navigation/deep links, widgets and an ordered implementation/test plan.

- [Product scope and decisions](docs/01-product-and-decisions.md)
- [Implementation and verification](docs/08-implementation-and-verification.md)
- [Apple technology references](docs/09-apple-technology-references.md)
- [Scaffold architecture alignment](docs/10-scaffold-architecture-verification.md)

The iOS source lives in `ios/ProjectAlpha`. Android and backend are future architecture placeholders, not part of the current runtime. The design documents describe intended behavior; they do not imply that the scaffold already implements it.
