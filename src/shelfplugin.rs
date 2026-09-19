// B1, in GM's own sentence: "Enable shelf checked in Settings = shelf in bar automatically,
// unchecked = no shelf in bar". The shelf is a separate Omarchy plugin, so that switch is what
// installs it. The package ships the plugin's files as data beside the UI; turning the switch on
// copies them into the user's own plugin directory and asks Omarchy to enable it, turning it off
// asks Omarchy to disable it. Every bar action is a stock omarchy command, hard rule 2.

use crate::json;
use crate::userfile;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const ID: &str = "io.github.thisisgm.flea-shelf";

// An empty FLEA_SHELF would resolve manifest.json against the working directory, so it is no
// candidate, the same rule paths.rs applies to FLEA_UI.
fn env_source() -> Option<PathBuf> {
    let value = std::env::var("FLEA_SHELF").ok()?;
    if value.is_empty() {
        return None;
    }
    Some(PathBuf::from(value))
}

// The plugin ships as data, so it is found the way paths::ui_dir finds the UI.
pub fn source() -> Option<PathBuf> {
    if let Some(p) = env_source() {
        if p.join("manifest.json").is_file() {
            return Some(p);
        }
    }
    let packaged = PathBuf::from("/usr/share/flea/shelf");
    if packaged.join("manifest.json").is_file() {
        return Some(packaged);
    }
    let exe = std::env::current_exe().ok()?;
    let dev = exe.parent()?.parent()?.parent()?.join("shelf");
    if dev.join("manifest.json").is_file() {
        return Some(dev);
    }
    None
}

// Where Omarchy looks for a user's own plugins, one folder per id.
pub fn installed() -> Result<PathBuf, String> {
    Ok(userfile::config_home()?.join("omarchy").join("plugins").join(ID))
}

// Sample manifest, the two keys read here being the only ones this file cares about:
// {"schemaVersion": 1, "id": "io.github.thisisgm.flea-shelf", "version": "0.3.0", ...}
fn version(dir: &Path) -> Option<String> {
    json::field_str(&std::fs::read_to_string(dir.join("manifest.json")).ok()?, "version")
}

// Files and never a symlink: a link into /usr/share would leave the plugin dead after an upgrade
// replaced it, and `omarchy plugin remove` expects a folder it can delete.
fn install(source: &Path, dest: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dest).map_err(|e| format!("{} could not be created ({})", dest.display(), e))?;
    for entry in std::fs::read_dir(source).map_err(|e| format!("{} could not be read ({})", source.display(), e))? {
        let entry = entry.map_err(|e| format!("{} could not be read ({})", source.display(), e))?;
        let from = entry.path();
        if from.is_dir() {
            return Err(format!("the shelf plugin holds a folder, {}, and this installer copies a flat one", from.display()));
        }
        let to = dest.join(entry.file_name());
        std::fs::copy(&from, &to).map_err(|e| format!("{} could not be copied ({})", from.display(), e))?;
    }
    // A file this Flea no longer ships would otherwise outlive the upgrade that dropped it.
    for entry in std::fs::read_dir(dest).map_err(|e| format!("{} could not be read ({})", dest.display(), e))? {
        let entry = entry.map_err(|e| format!("{} could not be read ({})", dest.display(), e))?;
        if !source.join(entry.file_name()).exists() {
            let _ = std::fs::remove_file(entry.path());
        }
    }
    Ok(())
}

// omarchy's own subcommands resolve their helpers through OMARCHY_PATH, which a session that did not
// come from a login shell does not carry; see the KB's omarchy_cli_needs_omarchy_path.
fn omarchy(args: &[&str]) -> Result<(), String> {
    let mut command = Command::new("omarchy");
    command.args(args);
    if std::env::var("OMARCHY_PATH").map(|v| v.is_empty()).unwrap_or(true) {
        command.env("OMARCHY_PATH", "/usr/share/omarchy");
    }
    let out = command.output().map_err(|e| format!("omarchy {} could not run ({})", args.join(" "), e))?;
    if out.status.success() {
        return Ok(());
    }
    let said = String::from_utf8_lossy(&out.stderr);
    let first = said.lines().find(|l| !l.trim().is_empty()).unwrap_or("it said nothing").trim().to_string();
    Err(format!("omarchy {} refused: {}", args.join(" "), first))
}

// The catalog knows the folders it has scanned, so a plugin copied in this second is unknown to
// `omarchy plugin enable` until the shell has been asked to look again. This is the stock fallback
// every omarchy-plugin-* command names in its own failure message.
fn rescan() {
    let _ = Command::new("omarchy-shell").args(["shell", "rescanPlugins"]).output();
}

// The switch itself, both ways.
pub fn sync(enabled: bool) -> Result<(), String> {
    let dest = installed()?;
    if !enabled {
        // Never installed here means nothing to disable, and asking would only print a refusal.
        if !dest.join("manifest.json").is_file() {
            return Ok(());
        }
        return omarchy(&["plugin", "disable", ID]);
    }
    let source = source().ok_or_else(|| "the shelf plugin is not installed, look for /usr/share/flea/shelf".to_string())?;
    if version(&dest) != version(&source) {
        install(&source, &dest)?;
    }
    rescan();
    omarchy(&["plugin", "enable", ID])
}

// Startup, where the copy is refreshed after an upgrade shipped a new plugin under an old switch.
// A switch that is off owns no copy, so there is nothing to carry forward.
pub fn refresh(enabled: bool) -> Result<(), String> {
    if !enabled {
        return Ok(());
    }
    let (dest, source) = (installed()?, source());
    let source = match source {
        Some(source) => source,
        None => return Ok(()),
    };
    if version(&dest) == version(&source) {
        return Ok(());
    }
    sync(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str, version: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("flea-shelfplugin-{}-{}", name, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("the fixture root");
        std::fs::write(dir.join("manifest.json"),
                       format!("{{\n  \"schemaVersion\": 1,\n  \"version\": \"{}\"\n}}\n", version)).expect("a manifest");
        std::fs::write(dir.join("Panel.qml"), "Item {}\n").expect("a panel");
        dir
    }

    #[test]
    fn the_manifest_names_the_version_and_not_the_schema_s() {
        let dir = fixture("version", "0.3.0");
        assert_eq!(version(&dir).as_deref(), Some("0.3.0"));
        assert_eq!(version(&dir.join("nowhere")), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_install_leaves_the_copy_and_drops_what_this_flea_no_longer_ships() {
        let source = fixture("source", "0.3.0");
        let dest = fixture("dest", "0.2.9");
        std::fs::write(dest.join("Gone.qml"), "Item {}\n").expect("a file from the older plugin");
        install(&source, &dest).expect("the copy");
        assert_eq!(version(&dest).as_deref(), Some("0.3.0"));
        assert!(dest.join("Panel.qml").is_file());
        assert!(!dest.join("Gone.qml").exists(), "the older plugin's file outlived the upgrade");
        assert!(!dest.join("Panel.qml").symlink_metadata().expect("the copy").file_type().is_symlink());
        let _ = std::fs::remove_dir_all(&source);
        let _ = std::fs::remove_dir_all(&dest);
    }

    #[test]
    fn a_folder_inside_the_plugin_is_refused_rather_than_silently_dropped() {
        let source = fixture("nested", "0.3.0");
        std::fs::create_dir_all(source.join("inner")).expect("a folder");
        let dest = fixture("nested-dest", "0.2.9");
        let said = install(&source, &dest).expect_err("a flat installer must say so");
        assert!(said.contains("flat one"), "{}", said);
        let _ = std::fs::remove_dir_all(&source);
        let _ = std::fs::remove_dir_all(&dest);
    }

    #[test]
    fn the_plugin_lands_where_omarchy_looks_for_a_user_s_own() {
        let path = installed().expect("a config directory");
        assert!(path.ends_with("omarchy/plugins/io.github.thisisgm.flea-shelf"), "{}", path.display());
    }
}
