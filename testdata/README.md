# compat testdata

`action_runner` の compat fixture 置き場。

各 fixture directory は最低でも次を持つ。

- `fixture.txt`
- `workflow.yml`

必要に応じて次も持てる。

- `event.json`

`fixture.txt` は当面 line-based の `key=value` 形式にする。

必須 key:

- `id`
- `source`
- `mode`
- `kind`
- `url`

任意 key:

- `added_at`
- `notes`
- `docs_urls`

`docs_urls` は `;` 区切りで GitHub Docs の根拠 URL を並べる。
特に upstream fixture を正規化して移植したケースでは、
期待値がどの GitHub Docs に基づくかをここに残す。

`event.json` は runner 実行時に `PushEvent` へ変換される push webhook payload。
`compat_fixture_test.mbt` の helper から `parse_github_push_event_json` を通して読み出せる。

`mode` は `supported` / `unsupported` / `known_diff` を想定する。
`kind` は当面 `parse` / `lower` / `run` / `trigger` を想定する。
