# 📄 feishu-toolkit（Hermes / Open API only）

> **English**: A stable Feishu document workflow for Hermes that uses only the Open API path based on `FEISHU_APP_ID` and `FEISHU_APP_SECRET`.
>
> **中文**：面向 Hermes 的飞书文档稳定工作流，只保留基于 `FEISHU_APP_ID` 和 `FEISHU_APP_SECRET` 的 Open API 路径。

[![Feishu](https://img.shields.io/badge/Feishu-OpenAPI-green)](https://open.feishu.cn)
[![Hermes](https://img.shields.io/badge/Hermes-Skill-blue)](https://github.com/NousResearch/hermes-agent)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## Why this branch exists

This branch keeps only the **stable Open API workflow** and removes OAuth callback guidance entirely.

It is intended for environments where:

- `FEISHU_APP_ID` and `FEISHU_APP_SECRET` are already configured
- OAuth callback flows are brittle or unnecessary
- you need reliable read/write automation for Feishu wiki/docx content

Removed on purpose:

- OAuth auth-link flow
- redirect URI setup instructions
- localhost/public callback troubleshooting

Kept on purpose:

- tenant access token exchange
- wiki token → docx token resolution
- raw content reads
- block-based overwrite writes

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

### 2. Resolve wiki token to doc token

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

### 4. Overwrite a document safely

The write path is:

1. list document blocks
2. patch title block
3. delete old root children
4. create new paragraph children in chunks
5. read back with `raw_content`

---

## Required permissions

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

## Important implementation notes

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

### Delete old body blocks

Use:

- `DELETE /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>/children/batch_delete`

Body:

```json
{
  "start_index": 0,
  "end_index": <child_count>
}
```

**Important:** `end_index` behaves as an exclusive bound in practice.
If there is 1 child, deleting it requires `end_index: 1`.

### Recreate body blocks

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
- chunk writes at ~50 lines per request
- verify with `raw_content`

---

## Minimal Python example

```python
import os, json, ssl, uuid, urllib.request, urllib.error

APP_ID = os.environ['FEISHU_APP_ID']
APP_SECRET = os.environ['FEISHU_APP_SECRET']


def req(method, url, data=None, headers=None):
    body = None if data is None else json.dumps(data, ensure_ascii=False).encode('utf-8')
    request = urllib.request.Request(url, data=body, method=method)
    final_headers = {'Content-Type': 'application/json; charset=utf-8'}
    if headers:
        final_headers.update(headers)
    for k, v in final_headers.items():
        request.add_header(k, v)
    try:
        with urllib.request.urlopen(request, context=ssl.create_default_context()) as r:
            return r.status, json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        payload = e.read().decode('utf-8', errors='ignore')
        try:
            return e.code, json.loads(payload)
        except Exception:
            return e.code, {'raw': payload}


_, token_resp = req('POST', 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal', {
    'app_id': APP_ID,
    'app_secret': APP_SECRET,
})
headers = {'Authorization': f"Bearer {token_resp['tenant_access_token']}"}

wiki_token = 'LDx2wLgkwiEEmjknHOoctC8jnff'
_, node = req('GET', f'https://open.feishu.cn/open-apis/wiki/v2/spaces/get_node?token={wiki_token}', headers=headers)
doc_id = node['data']['node']['obj_token']

_, blocks = req('GET', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks?page_size=500', headers=headers)
root = blocks['data']['items'][0]
root_id = root['block_id']
child_count = len(root.get('children', []))

req('PATCH', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{root_id}', {
    'update_text': {
        'elements': [{'text_run': {'content': '新标题'}}],
        'style': {'align': 1},
        'fields': [1]
    }
}, headers)

if child_count:
    req('DELETE', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{root_id}/children/batch_delete', {
        'start_index': 0,
        'end_index': child_count
    }, headers)

lines = ['第一行', '第二行', '第三行']
for i in range(0, len(lines), 50):
    chunk = lines[i:i+50]
    children = [
        {'block_type': 2, 'text': {'elements': [{'text_run': {'content': line}}]}}
        for line in chunk
    ]
    req('POST', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{root_id}/children?index={i}&client_token={uuid.uuid4()}', {
        'index': i,
        'children': children,
    }, headers)

_, raw = req('GET', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/raw_content', headers=headers)
print(raw['data']['content'])
```

---

## Repository layout

```text
feishu-doc-manager/
├── SKILL.md
├── README.md
├── LICENSE
└── install.sh
```

---

## License

MIT
