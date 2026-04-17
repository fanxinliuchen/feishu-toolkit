# 📄 feishu-toolkit

> **English**: A stable Hermes skill for reading and writing Feishu docs through the Open API using `FEISHU_APP_ID` and `FEISHU_APP_SECRET`.
>
> **中文**：一个面向 Hermes 的稳定飞书技能，使用 `FEISHU_APP_ID` 和 `FEISHU_APP_SECRET` 通过 Open API 读写飞书文档。

[![Feishu](https://img.shields.io/badge/Feishu-OpenAPI-green)](https://open.feishu.cn)
[![Hermes](https://img.shields.io/badge/Hermes-Skill-blue)](https://github.com/NousResearch/hermes-agent)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## What this repo contains

This repository contains a **Hermes skill** focused on a single stable workflow:

- exchange `FEISHU_APP_ID` + `FEISHU_APP_SECRET` for a tenant token
- resolve a wiki token to a real doc token
- read `raw_content`
- overwrite a doc safely through block APIs

It is designed for repeatable automation such as:

- wiki/doc readers
- report publishing
- note synchronization
- generated indexes and dashboards

---

## Required environment variables

- `FEISHU_APP_ID`
- `FEISHU_APP_SECRET`

---

## Recommended permissions

```json
{
  "scopes": {
    "tenant": [
      "docx:document",
      "docx:document:create",
      "docx:document:write_only",
      "wiki:wiki",
      "docs:permission.member",
      "contact:user.base:readonly"
    ]
  }
}
```

---

## Stable workflow

### 1. Get tenant token

```bash
curl -sS -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_id": "'$FEISHU_APP_ID'",
    "app_secret": "'$FEISHU_APP_SECRET'"
  }'
```

### 2. Resolve a wiki token

```bash
curl -sS 'https://open.feishu.cn/open-apis/wiki/v2/spaces/get_node?token=<WIKI_TOKEN>' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

Useful fields:

- `data.node.obj_type`
- `data.node.obj_token`
- `data.node.title`

### 3. Read raw content

```bash
curl -sS 'https://open.feishu.cn/open-apis/docx/v1/documents/<DOC_TOKEN>/raw_content' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

### 4. Overwrite a document

Recommended write sequence:

1. list document blocks
2. patch the root title block
3. delete old root children
4. create new paragraph blocks in chunks
5. verify with `raw_content`

---

## Important implementation details

### Patch title block

Use:

- `PATCH /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>`

Body:

```json
{
  "update_text": {
    "elements": [{"text_run": {"content": "新标题"}}],
    "style": {"align": 1},
    "fields": [1]
  }
}
```

### Delete old children

Use:

- `DELETE /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>/children/batch_delete`

Body:

```json
{
  "start_index": 0,
  "end_index": <child_count>
}
```

In practice, `end_index` behaves as an exclusive bound.

### Create new children

Use:

- `POST /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>/children`

Body:

```json
{
  "index": 0,
  "children": [
    {
      "block_type": 2,
      "text": {
        "elements": [
          {"text_run": {"content": "第一行"}}
        ]
      }
    }
  ]
}
```

Recommended:

- one paragraph per line
- chunk large writes at around 50 lines per request
- always verify with `raw_content`

---

## Install into Hermes

### Option 1: clone manually

```bash
mkdir -p ~/.hermes/skills/productivity
cd ~/.hermes/skills/productivity
git clone https://github.com/fanxinliuchen/feishu-toolkit.git
```

### Option 2: run install script

```bash
curl -sSL https://raw.githubusercontent.com/fanxinliuchen/feishu-toolkit/main/install.sh | bash
```

---

## Repository layout

```text
feishu-toolkit/
├── SKILL.md
├── README.md
├── LICENSE
└── install.sh
```

---

## License

MIT
