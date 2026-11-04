# 加急审核请求草稿（2026-11-04）

## 事实基础

| 项 | 值 |
|---|---|
| App | HomeBuddy（macOS，照片整理） |
| 版本 / 构建 | 1.0 / build 2 |
| 提交时间 | 2026-10-28 09:11（北京时间）＝ 2026-10-27 18:11（太平洋时间） |
| 截至起草 | 2026-11-04 14:23，等待 **7 天 5 小时** |
| 状态 | `WAITING_FOR_REVIEW`，从未进入 `IN_REVIEW` |
| 审核反馈 | 无拒信、无 Resolution Center 消息 |
| 首发？ | 是 |
| 定价 / 内购 / 账号 | $0.99 一次性买断 / 无内购 / 无需账号 |

---

## 提交路径（订正）

**App Store Connect 里没有加急表单。** 版本页面上那个「Waiting for Review」只能看状态，不能提交任何东西；Resolution Center 在苹果主动发消息之前也是只读的。

加急审核在开发者网站上，是独立表单：

```
https://developer.apple.com/contact/app-store/?topic=expedite
```

未登录会 302 跳到 Apple ID 登录页（`idmsa.apple.com`），登录后才是表单：选 app + 平台 → 填理由 → 提交。

入口也可以在 App Store Connect 里找：右上角「?」→ Contact Us → App Review。

## 官方口径（2026-11-04 抓的原文）

> App Review works around the clock with the goal of reviewing at least 50% of submissions in less than 24 hours and 90% in less than 48 hours. However, if you're facing extenuating circumstances, such as fixing a critical bug or timing your release to coincide with an event, you can request an expedited review.

> Expedite requests should be reserved for matters of genuine urgency.

也就是说：苹果自己承诺 90% 在 48 小时内出结果。**我们等了 7 天，已经落在他们承诺之外**，这是最有说服力的一条依据，比编一个发布节点强。

---

## 版本 A：加急审核表单正文（英文，可直接粘贴）

```
App: HomeBuddy (macOS), version 1.0, build 2, first release.

We submitted this build on 27 October 2026 at 18:11 PDT. As of today,
4 November 2026, it has been in Waiting for Review for seven days and has
never moved to In Review. We have received no rejection, no message in
Resolution Center, and no request for information.

We understand expedited review is meant for time-sensitive situations,
and we are not claiming an emergency. We are asking for one because a
first submission sitting untouched for a full week is outside what we can
plan around: a follow-up build (localization and a batch-recognition
screen) is finished and waiting on this review to conclude, and every
additional day of silence makes it harder to tell whether we have a bug
in submission or simply a queue.

The build needs no account, no purchase, and no network. A reviewer can
launch it, grant Photo Library access, browse albums, and open a photo to
see metadata entirely offline. Face detection requires a local model file
the user supplies; the app bundles no model weights. Review notes in App
Store Connect spell this out.

If an expedite is not possible, a one-line status update would help us
plan: is the build correctly queued, or is something in the submission
holding it back?

Contact: <your Apple ID email>
App ID: <App ID>
```

---

## 版本 B：Resolution Center 短信（英文，较短）

```
Hello, HomeBuddy 1.0 (build 2) has been in Waiting for Review since
27 October 18:11 PDT, seven days with no status change and no feedback.
This is our first release. Could someone confirm the submission is
correctly queued? A follow-up build is ready and waiting on this review,
so we would also appreciate an expedited review if that is possible.
Thank you.
```

---

## 版本 C：先问状态，不消耗加急（推荐先发这个）

加急要留给真的紧急。更稳的顺序是先发一封状态咨询，24 到 48 小时没回音再提加急。

App Store Connect → 右上角「?」→ Contact Us → App Review →「Contact App Review for help with a submission」

```
Subject: HomeBuddy 1.0 (build 2) in Waiting for Review for 7 days

Hello,

HomeBuddy 1.0, build 2, is our first macOS submission. We submitted it on
27 October 2026 at 18:11 PDT. It has been in Waiting for Review for seven
days and has never moved to In Review. There is no rejection and no
message in Resolution Center.

We are not asking to jump the queue. We would like to know whether the
submission is correctly queued and complete on our side, or whether
something is holding it back that we can fix. If there is anything
missing in the review notes or metadata, tell us and we will supply it
the same day.

App ID: <App ID>
Submission ID: <Submission ID>
```

**为什么先发这个**：官方承诺 90% 在 48 小时内出结果，问一句「是不是我们这边缺东西」属于正当咨询，苹果通常会回。加急额度有限，留到真有节点的时候用。

## 提交后的预期

- 加急审核通常在 **24 小时内**得到回复，可能是同意，也可能是模板拒绝
- 被拒不影响正常排队，不会让审核变慢
- 如果 48 小时仍无回应，走电话：开发者支持 → App 审核状态咨询（中国大陆区可约中文）

## 不要做的

- 不要写「我们的发布活动在 X 月 X 日」这类编造的时间节点。审核团队查得到，一次被发现会影响后续所有申请的可信度
- 不要在同一天重复提交多份加急申请
- 不要在加急请求里夹带功能说明。审核员看的是排队问题，不是产品介绍
