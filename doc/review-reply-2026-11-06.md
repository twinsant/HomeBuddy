# App Review 回复草稿（2026-11-06）

> 对应拒信：Submission 08f65627-688d-44ef-b68b-6b74f46b6330
> 两个问题：Guideline 2.1（人脸数据说明）+ 2.1(a)（侧栏无法滚动）
> 处理：隐私政策已加「Face data」章节并上线；侧栏改成显式 ScrollView；build 3 已上传

---

## 回复正文（英文，粘进 Resolution Center）

```
Hello,

Thank you for the review. Both items are addressed below.

--- Guideline 2.1, face data ---

1. What face data the app collects
The app collects three things, all produced on the user's Mac:
- face bounding-box coordinates for each detected face
- a 512-dimension face embedding per face (ArcFace 512, model antelopev2 supplied by the user)
- a person name the user assigns when they confirm a match
The app does not store face crops, and it does not upload photos. Detection runs
in-process through a bundled bridge; the model file is loaded from where the user
put it.

2. Use, sharing, retention, deletion and storage
Use: embeddings are compared by similarity so the user can group faces into people
and browse or search photos by person. The app performs no identity verification,
matches nothing against an external face database, and does not use face data to
train any model.

Sharing: none. There is no account system, no analytics, no advertising and no
tracking SDK. We, the developers, never receive face data, and we operate no server
that stores it.

Storage: embeddings are written to the Chroma collection configured in Settings,
by default http://localhost:8000, which is a service on the user's own Mac. Person
names and bounding boxes are written to a local SQLite file, by default
~/.homebuddy/photo-metadata.sqlite.

Retention: no automatic expiry. The data stays in those two local locations until
the user deletes it.

Deletion: deleting the local SQLite file removes person names and bounding boxes;
deleting the collection on the user's own Chroma service removes the embeddings.
The app never holds a second copy to synchronise.

3. Third parties
None. The single case in which face data leaves the device is deliberate and
user-initiated: if the user changes the Chroma address in Settings to a remote host
and saves it, embeddings are sent to that address. That recipient is the service the
user configured, not us.

4. Retention period
Indefinite until the user deletes it, as described above. There is no server-side
copy and therefore no server-side retention period.

5. Where the privacy policy explains this
Policy: https://www.twinsant.com/homebuddy/privacy
Section heading: "Face data" (English version). The Chinese version of the same
section is titled "人脸数据". The policy was updated today, 6 November 2026, to add
this section; the previous version described face data only in passing.

6. Quoted text from the policy

"What we collect: face detection runs on your Mac using a model file you supply.
For each photo the app produces face bounding-box coordinates, a 512-dimension face
embedding, and the person name you assign. Face crops are not saved and original
photos are not uploaded."

"How it is used: embeddings are grouped by similarity into people so you can browse
and search photos by person. Nothing else. They are not used to identify who someone
really is, and not used to train models."

"Where it is stored: embeddings are written to the Chroma collection configured in
Settings, by default http://localhost:8000, a service on your own Mac. Person names
and bounding boxes are written to the local SQLite file, by default
~/.homebuddy/photo-metadata.sqlite."

"Sharing with third parties: none. There is no account system, no analytics,
advertising or tracking SDK. We, the developers, never receive face data and hold no
server that stores it."

"The single exception: if you change the Chroma address in Settings to a remote host
and save it, face embeddings are sent to that address. The recipient is the service
you configured, not us."

"Retention: no automatic expiry. Data stays in those two local locations until you
delete it."

"Deletion: deleting the local SQLite file removes person names and bounding boxes;
deleting the collection on your own Chroma service removes the embeddings. This
version does not sync deletions across devices."

--- Guideline 2.1(a), sidebar scrolling ---

You are right, and it was reproducible. The sidebar was built as a List inside the
NavigationSplitView sidebar column. Rows below the fold could not be reached because
the list never received a scrollable area in that column.

Fixed in build 3, uploaded today: the sidebar is now an explicit ScrollView with a
LazyVStack and visible scroll indicators, so scrolling no longer depends on how List
behaves in the sidebar column. All seven sections (disk directories, people, videos,
system albums) are reachable on a 14-inch MacBook Pro, and the fix also works when
the window is short.

Build 3 is version 1.0 (3), currently in App Store Connect. Please review it in place
of build 2.

Thank you.
```

---

## 提交前要做的三件

1. build 3 上传并处理完（`fastlane mac upload pkg:build/mac-app-store/HomeBuddy.pkg`）
2. 在 ASC 里把版本构建设置指向 build 3（如果自动选最新则跳过）
3. 回复后**不要**再改元数据或截图，等审核
