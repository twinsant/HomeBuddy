``
Hello,

Thank you for the second review. We are answering all three items, and we have
also rewritten the App Review Information notes in App Store Connect so the
demo steps and the face-data explanation are stored with the build rather than
only in this thread.

--- Guideline 2.1, face data: full answers ---

1) What face data the app collects
- A bounding box (four numbers) for each detected face.
- A 512-dimension embedding per detected face, computed on the Mac by a model
  file the user supplies. The app bundles no model weights and downloads none.
- A person name that the user types when confirming a match.
- The app does NOT collect face crops, does NOT collect photos for upload, and
  does NOT read any face data from any external source.

2) Planned use
- Group faces into people by similarity, so the user can browse and search
  their own photos by person.
- Nothing else. No identity verification, no matching against an external face
  database, no emotion or age inference, no training or model improvement.

3) Sharing and storage
- Shared with third parties: none. We, the developers, never receive face data.
  There is no account system and no server that stores it.
- Stored on the user's Mac in two places:
  a) embeddings: the Chroma collection the user configures in Settings, default
     http://localhost:8000, which is a service on the same Mac;
  b) names and bounding boxes: a local SQLite file, default
     ~/.homebuddy/photo-metadata.sqlite inside the app container.
- The only way face data leaves the device is a deliberate, user-initiated act:
  if the user changes the Chroma address to a remote host and saves it, the
  embeddings go to that host. That host is the user's choice, not ours.

4) Retention
- No automatic expiry. The data stays in those two local locations until the
  user deletes it. There is no server-side copy, so there is no server-side
  retention period.

5) Where the privacy policy explains this
- Policy URL: https://www.twinsant.com/homebuddy/privacy
- Section heading: "Face data" (English), "人脸数据" (Chinese)
- The policy was updated on 6 November 2026 to add this section.
- Supporting sections: "Where data is stored", "When data leaves the device",
  "Deleting data".

6) Quoted text from that section

"What we collect: face detection runs on your Mac using a model file you
supply. For each photo the app produces face bounding-box coordinates, a
512-dimension face embedding, and the person name you assign. Face crops are
not saved and original photos are not uploaded."

"How it is used: embeddings are grouped by similarity into people so you can
browse and search photos by person. Nothing else. They are not used to identify
who someone really is, and not used to train models."

"Where it is stored: embeddings are written to the Chroma collection configured
in Settings, by default http://localhost:8000, a service on your own Mac.
Person names and bounding boxes are written to the local SQLite file, by
default ~/.homebuddy/photo-metadata.sqlite."

"Sharing with third parties: none. There is no account system, no analytics,
advertising or tracking SDK. We, the developers, never receive face data and
hold no server that stores it."

"The single exception: if you change the Chroma address in Settings to a remote
host and save it, face embeddings are sent to that address. The recipient is the
service you configured, not us."

"Retention: no automatic expiry. Data stays in those two local locations until
you delete it."

"Deletion: deleting the local SQLite file removes person names and bounding
boxes; deleting the collection on your own Chroma service removes the
embeddings. This version does not sync deletions across devices."

--- Guideline 2.1(a): demo access ---

The app has no account and no login, so there is no demo account to issue. The
core features need no setup: launch, allow photo access, click an album, click a
photo to see its metadata. That path is offline and complete.

What you could not reach is face detection, which requires a local model file
the user supplies. We cannot ship those weights (licence), so here are two ways
forward, and we will do whichever you prefer:
  a) We ship a review-only build under a separate bundle identifier with a
     sample model and a sample photo folder inside the bundle. You then see the
     People feature end to end. Say the word and it will be uploaded within a
     day.
  b) You review the app as a photo organizer, with face detection documented as
     an optional local feature.

We have also written the full click path into App Review Information > Notes.

--- Guideline 2.4.5(i): photo library ---

We believe this refers to the photo library. The app uses only PhotoKit, the
public framework:
- PHPhotoLibrary.authorizationStatus(for: .read) and requestAuthorization(for: .read)
- PHAsset.fetchAssets / PHAssetCollection.fetchAssetCollections / PHFetchOptions
- PHImageManager and PHCachingImageManager for thumbnails and previews
- PHAssetResourceManager only when the user exports a copy into a folder they
  chose

Two facts worth stating:
1) PhotoKit offers only addOnly and readWrite as access levels; there is no
   read-only level, so readWrite is the documented way to read a library. The
   source contains no performChanges, no PHAssetChangeRequest and no
   PHAssetCollectionChangeRequest, so the app never writes to the library.
2) The disk folder scanner uses .skipsPackageDescendants, so a .photoslibrary
   package is never traversed and no file inside it is opened by path.

If a specific file path or API appeared in your tooling output, please tell us
which one and we will remove it. We could not reproduce a private-API access on
our side.

Thank you.