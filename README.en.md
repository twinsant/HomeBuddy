# HomeBuddy

HomeBuddy is a macOS photo organization tool. It browses the system Photos library, caches photo metadata, performs local face detection and person labeling, and optionally uses Ollama for image descriptions.

> The project is currently under development. Before publishing the repository or distributing the app, read the [security and privacy audit](doc/security-privacy-audit-2026-09-24.md).

## Features

- Browse the system Photos library, smart albums, and user albums.
- Inspect photo dimensions, format, capture date, camera, lens, exposure, ISO, and focal length.
- Cache photo metadata and Ollama descriptions in SQLite.
- Run local face detection and generate embeddings with a `face-detect.cpp`-compatible `antelopev2.gguf` model.
- Create person labels, store confirmed face embeddings in Chroma, and query possible matches.
- Analyze individual photos or batches with an Ollama vision model and search photos by recognized text.
- Use macOS security-scoped bookmarks for user-selected model files and SQLite storage directories.

## Requirements

- macOS 26.5 or later
- Xcode 27 or later
- Swift 5
- Photos library permission
- For local face recognition: a `face-detect.cpp`-compatible `antelopev2.gguf` model
- Optional image descriptions: a running [Ollama](https://ollama.com/) instance and a vision-capable model
- Optional face-vector indexing: a running [Chroma](https://www.trychroma.com/) HTTP service

The app has no separate package-manager dependencies. Native dependencies are committed as static libraries under `HomeBuddy/Native/lib/`. Release tooling uses Bundler to manage fastlane.

## Build and Run

1. Clone the repository and open `HomeBuddy.xcodeproj` in Xcode.
2. Select the `HomeBuddy` scheme and a local macOS destination.
3. Build or run the app from Xcode.
4. On first launch, grant Photos library access in macOS settings.
5. Open the app settings and select an `antelopev2.gguf` model file.
6. For Ollama, make sure the service is running, select a vision model, and save the address.
7. For Chroma, start the Chroma HTTP service, configure the tenant, database, and collection, then test the connection.

Default service addresses:

- Ollama: `http://127.0.0.1:11434`
- Chroma: `http://localhost:8000`

The app accepts manually entered service addresses. For remote services, use HTTPS, authentication, and restricted network access; the current client does not provide these protections automatically.

## Mac App Store Release

The fastlane configuration provides `mac test`, `mac build`, and `mac upload` lanes. See the [release guide (Chinese)](doc/mac-app-store-release.md) for signing, environment variables, commands, and the pre-submission checklist. Uploading does not submit the app for review or release it automatically.

## Data and Privacy

- Photos are read from the system Photos library by default. HomeBuddy does not automatically copy originals into the repository directory.
- Metadata, person names, face boxes, and Ollama descriptions are written to a SQLite cache. The default cache location is `~/.homebuddy/photo-metadata.sqlite`; if that location cannot be used, the app tries macOS Application Support. A different directory can be selected in Settings.
- Ollama image analysis sends photo data to the configured Ollama address. The default is a local loopback address, but users can configure a remote address.
- Chroma receives face embeddings. Confirmed face records also contain a photo identifier, person ID, display name, and model ID.
- Selecting a local face model does not copy the model into the repository. The model is accessed through a security-scoped bookmark.
- Clearing the local cache does not currently guarantee that remote Chroma data has been deleted. Deletion and synchronization are still being improved.

Do not commit real photos, SQLite databases, model weights, or personal configuration to Git. Before making the repository public, inspect the full Git history, not only the current working tree.

## Permissions

The app enables App Sandbox, Hardened Runtime, Photos library access, and read/write access to user-selected files. macOS displays the relevant permission prompts when the app first accesses Photos or a user-selected model or storage directory.

## Third-party Components and Licenses

Native libraries and their licenses are stored under `HomeBuddy/Native/`. The directory currently includes files related to `face-detect.cpp`, ggml, and libjpeg-turbo, together with license texts. Before distribution, verify the version, source, license, and usage restrictions for every static library, model weight, and Ollama model.

The app UI states that the `antelopev2.gguf` pretrained weights are for non-commercial use only. Follow the latest license provided by the model publisher.

## Testing

Run from the project directory:

```sh
xcodebuild test -project HomeBuddy.xcodeproj -scheme HomeBuddy -destination 'platform=macOS'
```

The exact macOS test destination depends on the Xcode installation and version on the host machine.

## Known Limitations

- Ollama and Chroma URLs accept arbitrary user input; remote HTTPS and authentication must be enforced by the deployment environment.
- The current version does not provide complete local-cache clearing, durable remote-vector deletion retries, or synchronization when photos are deleted.
- Native dependencies are committed build artifacts; dependency upgrades should update their sources, licenses, and build documentation together.

## Contributing

When opening an issue or pull request, do not attach real photos, databases, model files, personal logs, or service credentials. For security issues, avoid publishing exploitable details publicly and contact the maintainer privately first.
