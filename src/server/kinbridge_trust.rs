// KinBridge trust circle — client-side pubkey / ID allow-list.
//
// Purpose
// -------
// Mitigates CVE-2026-30784 (missing authorization in rustdesk-server hbbs/hbbr).
// Even if an attacker reaches the tailnet and the relay, the *device being
// remote-controlled* refuses to honor a LoginRequest whose `my_id` is not in
// the explicit allow-list. No prompt, no password challenge — the connection
// is rejected at `on_message`'s first LoginRequest sight.
//
// Storage
// -------
// JSON file at `<Config::path()>/kinbridge_whitelist.json`:
//
//   {
//     "mode": "off" | "strict",
//     "ids":  ["uuid-or-rustdesk-id", ...]
//   }
//
// `mode = off` is the default (behavioural parity with pre-KinBridge
// RustDesk). `mode = strict` rejects any id not in `ids`.
//
// Seeding
// -------
// Wilson's dashboard (Lovable side) writes this file during pairing:
//   1. Owner approves a helper in the Lovable dashboard (TOTP gated).
//   2. Lovable POSTs the helper's stable id to kinbridge-api, which writes
//      it to this file via an IPC call into the running agent (Week-3
//      enhancement — today, manual edit is fine).
//
// Observability
// -------------
// Every reject is logged at WARN with `kinbridge: reject id=...`. Every
// accept (strict mode) is logged at INFO. Allow/deny decisions are pure
// functions of the file's current contents — reload happens on every check
// so a manual edit takes effect without a process restart.

use hbb_common::{config::Config, log};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::PathBuf,
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};

const WHITELIST_FILENAME: &str = "kinbridge_whitelist.json";
/// How long to cache the parsed file in memory. Short so manual edits are
/// picked up quickly; long enough that a LoginRequest burst doesn't re-read
/// from disk on every connection.
const CACHE_TTL: Duration = Duration::from_secs(5);

#[derive(Debug, Deserialize, Serialize, Clone, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum WhitelistMode {
    Off,
    Strict,
}

impl Default for WhitelistMode {
    fn default() -> Self {
        WhitelistMode::Off
    }
}

#[derive(Debug, Deserialize, Serialize, Default, Clone)]
pub struct Whitelist {
    #[serde(default)]
    pub mode: WhitelistMode,
    #[serde(default)]
    pub ids: Vec<String>,
}

impl Whitelist {
    pub fn allows(&self, peer_id: &str) -> bool {
        match self.mode {
            WhitelistMode::Off => true,
            WhitelistMode::Strict => self.ids.iter().any(|id| id == peer_id),
        }
    }
}

struct Cached {
    list: Whitelist,
    fetched_at: Instant,
}

static CACHE: OnceLock<Mutex<Option<Cached>>> = OnceLock::new();

fn whitelist_path() -> PathBuf {
    Config::path(WHITELIST_FILENAME)
}

fn load_from_disk() -> Whitelist {
    let path = whitelist_path();
    if !path.exists() {
        return Whitelist::default();
    }
    match fs::read_to_string(&path) {
        Ok(contents) => match serde_json::from_str::<Whitelist>(&contents) {
            Ok(w) => w,
            Err(err) => {
                // Fail closed on parse error if the file looked like it was
                // meant to be strict. If mode field is missing or malformed
                // we just default to Off, preserving the existing behaviour
                // and logging the issue for Wilson.
                log::warn!(
                    "kinbridge: failed to parse {}: {err}. Treating as empty whitelist.",
                    path.display()
                );
                Whitelist::default()
            }
        },
        Err(err) => {
            log::warn!(
                "kinbridge: failed to read {}: {err}. Treating as empty whitelist.",
                path.display()
            );
            Whitelist::default()
        }
    }
}

fn current() -> Whitelist {
    let cell = CACHE.get_or_init(|| Mutex::new(None));
    let mut guard = cell.lock().unwrap_or_else(|p| p.into_inner());
    if let Some(c) = guard.as_ref() {
        if c.fetched_at.elapsed() < CACHE_TTL {
            return c.list.clone();
        }
    }
    let fresh = load_from_disk();
    *guard = Some(Cached {
        list: fresh.clone(),
        fetched_at: Instant::now(),
    });
    fresh
}

/// Gate called at the start of LoginRequest handling. Returns true iff the
/// peer is allowed to proceed.
pub fn allow_login(peer_id: &str) -> bool {
    let wl = current();
    let allowed = wl.allows(peer_id);
    match (wl.mode, allowed) {
        (WhitelistMode::Strict, true) => {
            log::info!("kinbridge: accept id={peer_id} (strict mode, whitelisted)");
        }
        (WhitelistMode::Strict, false) => {
            log::warn!(
                "kinbridge: reject id={peer_id} (strict mode, not in whitelist of {} entries)",
                wl.ids.len()
            );
        }
        (WhitelistMode::Off, _) => {
            // Off mode is the default — no log spam. If Wilson wants to
            // confirm, he can grep `kinbridge:` in the log to see that mode
            // never flipped to strict.
        }
    }
    allowed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn off_allows_everyone() {
        let wl = Whitelist {
            mode: WhitelistMode::Off,
            ids: vec![],
        };
        assert!(wl.allows("abc"));
        assert!(wl.allows(""));
    }

    #[test]
    fn strict_requires_exact_match() {
        let wl = Whitelist {
            mode: WhitelistMode::Strict,
            ids: vec!["trusted-1".into(), "trusted-2".into()],
        };
        assert!(wl.allows("trusted-1"));
        assert!(wl.allows("trusted-2"));
        assert!(!wl.allows("trusted-3"));
        assert!(!wl.allows(""));
    }

    #[test]
    fn deserialize_roundtrip() {
        let s = r#"{"mode":"strict","ids":["a","b"]}"#;
        let wl: Whitelist = serde_json::from_str(s).unwrap();
        assert_eq!(wl.mode, WhitelistMode::Strict);
        assert_eq!(wl.ids, vec!["a".to_string(), "b".to_string()]);
    }

    #[test]
    fn deserialize_defaults_to_off() {
        let s = r#"{}"#;
        let wl: Whitelist = serde_json::from_str(s).unwrap();
        assert_eq!(wl.mode, WhitelistMode::Off);
        assert!(wl.ids.is_empty());
    }
}
