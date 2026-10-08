# Profil & Teman via GitHub

Neovarch has no server of its own for friends and profiles: **GitHub is the backend**.

- **Login**: "Masuk dengan GitHub" uses the OAuth **device flow**. It needs no client secret.
- **Profile**: your avatar, name, bio and login come from GitHub. The desktop core computes the rest:
  - an activity heatmap for the last 365 days: agent messages and tool calls per day, plus your GitHub contribution calendar (optional);
  - your top stack: languages from the file extensions the agent touched, the tools it used, and the top languages of your own repos;
  - a "lagi ngoding" (coding now) status: active when the agent ran or you typed in the desktop in the last 10 minutes. The project name is shown only if you opt in.
- **Publishing**: all of this goes as JSON into one **public Gist** with the file `neovarch-profile.json`. The Gist is created once and its id is remembered. It is updated at most every 5 minutes, and earlier when your coding status changes.
- **Friends**: friends are mutual follows (accounts you follow that also follow you). A friend's card is read from their public `neovarch-profile.json` Gist.

## One-time setup: create a GitHub OAuth App (client id)

Every Neovarch install needs an OAuth App client id. The device flow is public, so there is no secret to keep.

1. Open https://github.com/settings/developers → **OAuth Apps** → **New OAuth App**. For an organisation, use Organisation settings → Developer settings.
2. Fill in the form:
   - Application name: `Neovarch Agent` (any name works)
   - Homepage URL: `https://github.com/Maftuuh1922/neovrach_Agent` (any URL works)
   - Authorization callback URL: `http://127.0.0.1/` (the device flow does not use it, but GitHub requires one)
3. Click **Register application**, then tick **Enable Device Flow** and save.
4. Copy the **Client ID** (it looks like `Ov23li…` or `Iv1.…`). Do **not** generate a client secret; Neovarch never uses one.
5. Give the client id to Neovarch in one of these ways:
   - Desktop: **Profil & Teman** → paste it into the "Client ID GitHub" field. This saves `social.github_client_id` in `~/.neovarch/config.yaml`.
   - Environment variable: `NEOVARCH_GITHUB_CLIENT_ID=Ov23li…` (it wins over config.yaml). This suits packaged builds and CI.
   - Edit `~/.neovarch/config.yaml` by hand:
     ```yaml
     social:
       github_client_id: Ov23li...
     ```

Scopes requested: `read:user` (profile), `gist` (create/update the profile Gist) and `user:follow` (add or remove friends).

## Where the token lives

The access token is stored in the OS keychain when the Python `keyring` package can reach one (macOS Keychain, Windows Credential Manager, Secret Service on Linux). Without a keychain it is stored in `~/.neovarch/secrets/github_token` with mode `0600`. No route returns the token, and it is never logged. "Keluar" deletes it. Set `NEOVARCH_SECRET_BACKEND=file` to force the file store.

## Privacy toggles (`social.*` in config.yaml)

| key | default | effect |
| --- | --- | --- |
| `publish_heatmap` | true | include the 365-day counts in the Gist |
| `publish_stack` | true | include top languages and agent tools |
| `publish_status` | true | include `coding` and `last_active_at` |
| `share_project` | false | include the current project name while coding |
| `include_github_contributions` | true | merge the GitHub contribution calendar into the heatmap |
| `paused` | false | stop automatic publishing; nothing is sent until you resume or press "Publikasikan sekarang" |

## Rate limits

- Every GET is conditional (`If-None-Match` with the stored ETag) and cached for 5 minutes.
- On a 403 or 429 caused by rate limiting, the core backs off until `Retry-After` or `X-RateLimit-Reset`, and keeps serving the cached data in the meantime.
- Friend profiles are fetched at most 6 at a time.

## Core API (the phone uses these through the paired PC; it needs no GitHub login)

| route | what |
| --- | --- |
| `GET /api/social/status` | signed in?, client id configured?, login flow, settings, gist, last publish |
| `POST /api/social/login` / `GET /api/social/login` | start the device flow → `{user_code, verification_uri}` / poll its state |
| `POST /api/social/logout` | forget the token |
| `GET /api/social/profile` | your profile: GitHub fields, `heatmap`, `stack`, `status`, `publish` |
| `GET /api/social/friends` | `{friends:[card…], pending:[…], counts}` sorted coding first |
| `GET /api/social/friends/{login}` | friend detail, including their full published profile |
| `GET /api/social/search?q=` | GitHub user search, with follow state |
| `POST /api/social/follow {login}` / `DELETE /api/social/follow/{login}` | add a friend (follow) / unfriend (unfollow) |
| `GET/PUT /api/social/settings` | privacy toggles and client id |
| `POST /api/social/publish` | publish now |
| `POST /api/social/activity {project?}` | editor heartbeat for "lagi ngoding" |

The same calls exist as JSON-RPC methods: `social.status`, `social.profile`, `social.friends`, `social.friend {login}`, `social.search {q}`, `social.follow` / `social.unfollow {login}`, `social.settings`, `social.publish`, `social.login.start`, `social.logout`, `social.activity`.

Realtime: the core pushes `social.changed {what: login|profile|friends|status|settings}` on `/api/ws` and `/api/events`. Refetch the matching snapshot when it arrives.

## Published JSON (`neovarch-profile.json`, schema `neovarch-profile/1`)

```json
{
  "schema": "neovarch-profile/1", "app": "neovarch", "version": "1.4.0",
  "login": "aku", "name": "Aku Dev", "bio": "…", "avatar_url": "…", "html_url": "…",
  "updated_at": "2026-10-09T04:00:00Z",
  "heatmap": {"start": "2025-10-10", "end": "2026-10-09", "days": 365, "counts": [0, 3, …],
              "total": 812, "active_days": 190, "streak": 6, "max": 31},
  "stack": {"languages": [{"name": "Python", "share": 0.41, "source": "both"}],
            "tools": [{"name": "shell", "count": 120, "share": 0.3}]},
  "status": {"coding": true, "last_active_at": "2026-10-09T03:58:00Z", "project": "neovarch"}
}
```

`heatmap`, `stack` and `status` are left out when their toggle is off.
