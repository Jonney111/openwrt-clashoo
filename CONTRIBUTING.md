# Contributing / 贡献指南

Clashoo uses bilingual GitHub issues and pull requests. Chinese is welcome; keep commit and PR titles in concise English so release notes stay readable.

Clashoo 使用中英文双语 Issue 和 PR。正文可以中文优先；commit 和 PR 标题建议使用简洁英文，方便生成清晰的 release notes。

## Commit Format / Commit 格式

Use Conventional Commits:

```text
fix(dns): restore fallback-filter when leak protection is disabled

Fixes #23
```

Common types:

- `feat`: new user-facing behavior / 新功能
- `fix`: bug fix / 问题修复
- `perf`: performance or startup improvement / 性能或启动速度改进
- `refactor`: internal cleanup without behavior change / 内部重构
- `ci`: GitHub Actions, release, or feed changes / CI、发布、源同步
- `docs`: documentation / 文档
- `test`: tests or verification scripts / 测试
- `chore`: routine maintenance, rules, or core bumps / 维护、规则、内核更新

Preferred scopes:

```text
core, luci, dns, proxy, singbox, mihomo, smart, runtime,
firewall, update, release, ci, subs, profiles, rules, docs
```

## Issue References / Issue 关联

Use GitHub keywords when a commit or PR resolves an issue:

```text
Fixes #123
Closes #123
Resolves #123
```

Use `Refs #123` when the change is related but should not close the issue.

如果提交或 PR 会解决某个 Issue，请使用 `Fixes #123`、`Closes #123` 或 `Resolves #123`。只是关联但不关闭时使用 `Refs #123`。

## Pull Requests / PR 要求

Every PR should include:

- Summary / 变更摘要
- Related Issues / 关联 Issue
- Validation / 验证方式
- Notes / 备注

For device-sensitive changes, include OpenWrt version, architecture, package manager, core, and proxy mode.

涉及设备行为的修改，请说明 OpenWrt 版本、架构、包管理器、内核和代理模式。

## Release Notes / 发布说明

Release notes are grouped by commit type:

- `feat` -> New Features / 新功能
- `fix` -> Bug Fixes / 问题修复
- `perf`, `refactor` -> Improvements / 改进
- `ci`, `build` -> Build & Release / 构建与发布
- `docs` -> Documentation / 文档
- `chore` -> Maintenance / 维护

