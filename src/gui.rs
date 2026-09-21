use crate::paths;
use crate::thp;
use crate::vulkan;
use std::ffi::OsStr;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

// exec rather than spawn, so the shell replaces this process and no pid is orphaned.
pub fn exec_qs(ui: &Path, start: Option<&str>, select: Option<&str>) -> i32 {
    let mut cmd = qs_command(ui.join(paths::ENTRY));
    if let Some(path) = start {
        cmd.env("FLEA_PATH", path);
    }
    if let Some(target) = select {
        cmd.env("FLEA_SELECT", target);
    }
    exec(cmd)
}

// flea --pick <reply>: the picker window tools/flea-portal opens for one portal request. Same shell
// and the same renderer choice, on a second entry point, so a chooser is not a second application.
pub fn pick(reply: &str) -> i32 {
    // Empty is absent, the rule paths::has_display() applies: a wrapper's unset variable is not a request.
    if !std::env::var_os("FLEA_PICKER").is_some_and(|value| !value.is_empty()) {
        eprintln!("flea: --pick needs FLEA_PICKER, the portal request tools/flea-portal puts in the environment");
        return 2;
    }
    if reply.is_empty() {
        eprintln!("flea: --pick needs the reply file tools/flea-portal names, and it was empty");
        return 2;
    }
    if !paths::has_display() {
        eprintln!("flea: there is no graphical session to open a file chooser in");
        return 2;
    }
    let Some(ui) = paths::ui_dir() else {
        eprintln!("flea: the shell config is missing, set FLEA_UI or install /usr/share/flea/ui");
        return 2;
    };
    let mut cmd = qs_command(ui.join(paths::PICKER_ENTRY));
    cmd.env("FLEA_PICKER_REPLY", reply);
    exec(cmd)
}

// The qs invocation both entry points share: the target, the binary the shell calls back into, and
// the renderer, which is chosen here because this is the last point that can hand it to qs.
fn qs_command(target: PathBuf) -> Command {
    let mut cmd = Command::new("qs");
    cmd.arg("-p").arg(target);
    first_paint_colour(&mut cmd);
    skip_gtk_platform_theme(&mut cmd);
    // An explicit choice is the operator's, the same rule FLEA_UI and QSG_RHI_BACKEND follow here.
    // map_or, not is_none_or: that method landed in 1.82 and Cargo.toml declares a 1.77 floor.
    if std::env::var_os("FLEA_BIN").map_or(true, |value| value.is_empty()) {
        if let Ok(binary) = std::env::current_exe() {
            cmd.env("FLEA_BIN", binary);
        }
    }
    // Empty is absent, the rule paths::has_display() applies: a wrapper's unset variable is not a choice.
    if std::env::var_os("QSG_RHI_BACKEND").is_some_and(|value| !value.is_empty()) {
        // An explicit choice is the operator's, so it is neither replaced nor offered a retry.
        cmd.env_remove("FLEA_RENDERER_AUTOMATIC");
        // Vulkan on a hybrid GPU still has to present on the compositor's device; pinning is not a renderer change.
        if std::env::var_os("QSG_RHI_BACKEND").as_deref() == Some(OsStr::new("vulkan")) {
            pin_display_icd(&mut cmd, None);
        }
    } else {
        match vulkan::usable() {
            Err(reason) => {
                // A silent downgrade hides a 2.4x memory regression, so the reason the probe found is said once.
                eprintln!("flea: Vulkan is unusable, {reason}, so the shell starts on OpenGL");
                cmd.env("QSG_RHI_BACKEND", "opengl");
                cmd.env_remove("FLEA_RENDERER_AUTOMATIC");
            }
            Ok(devices) => {
                // Vulkan is the measured fast path, and the marker is what permits the QML arm its one retry.
                cmd.env("QSG_RHI_BACKEND", "vulkan");
                cmd.env("FLEA_RENDERER_AUTOMATIC", "1");
                pin_display_icd(&mut cmd, Some(&devices));
            }
        }
    }
    cmd
}

// `already` carries the automatic arm's probe result, so a hybrid launch does not pay for Vulkan twice.
fn pin_display_icd(cmd: &mut Command, already: Option<&[(u32, u32)]>) {
    if operator_chose_icd(
        std::env::var_os("VK_DRIVER_FILES").as_deref(),
        std::env::var_os("VK_ICD_FILENAMES").as_deref(),
    ) {
        return;
    }
    let owned;
    let devices = match already {
        Some(devices) => devices,
        None => match vulkan::usable() {
            Ok(devices) => {
                owned = devices;
                owned.as_slice()
            }
            Err(_) => return,
        },
    };
    apply_display_pin(cmd, vulkan::display_pin(devices));
}

// Split from pin_display_icd so a test can drive the guard without touching this process's environment.
fn operator_chose_icd(driver: Option<&OsStr>, icd: Option<&OsStr>) -> bool {
    driver.is_some_and(|value| !value.is_empty()) || icd.is_some_and(|value| !value.is_empty())
}

// Split from pin_display_icd so a test can drive the answer a single-GPU box can never produce.
fn apply_display_pin(cmd: &mut Command, pin: vulkan::DisplayPin) {
    match pin {
        vulkan::DisplayPin::NotNeeded => {}
        vulkan::DisplayPin::Unmatched { vendor } => {
            eprintln!("flea: Vulkan sees a GPU with no display, but no ICD file names vendor {vendor:#06x}, so the loader's own list stands");
        }
        vulkan::DisplayPin::Pin { icd, gpu } => {
            eprintln!("flea: Vulkan sees a GPU with no display, so the shell starts on {:#06x}:{:#06x} through {icd}", gpu.0, gpu.1);
            cmd.env("VK_DRIVER_FILES", &icd);
            cmd.env("VK_ICD_FILENAMES", &icd);
            cmd.env(vulkan::PIN_MARKER, "1");
        }
    }
}

// The entry maps its window before ui/Theme.qml compiles, so the colour comes from out here.
fn first_paint_colour(cmd: &mut Command) {
    cmd.env("FLEA_FIRST_PAINT", crate::tui::theme::Theme::load().background_hex);
}

// Omarchy's own platform theme, and the only one this trades away, see AGENTS.md "The first window".
const GTK3: &str = "gtk3";

// The launcher marks the theme it traded, so a program Flea opens gets it back.
pub const THEME_MARKER: &str = "FLEA_QT_THEME";

// gtk3 as Qt's platform theme starts GTK inside the shell for one string, the icon theme name.
fn skip_gtk_platform_theme(cmd: &mut Command) {
    // Empty is absent, the rule paths::has_display() applies: a wrapper's unset variable is not a choice.
    if std::env::var_os("QS_ICON_THEME").is_some_and(|value| !value.is_empty()) {
        return;
    }
    // Any other engine is the operator's own choice and is never traded.
    if std::env::var_os("QT_QPA_PLATFORMTHEME").as_deref() != Some(OsStr::new(GTK3)) {
        return;
    }
    let Some(home) = std::env::var_os("HOME") else { return };
    let path = PathBuf::from(home).join(".local/state/omarchy/current/theme/icons.theme");
    // Sample input, the whole file: "Yaru-purple\n"
    let Ok(text) = std::fs::read_to_string(path) else { return };
    let name = text.trim();
    if name.is_empty() {
        return;
    }
    cmd.env("QS_ICON_THEME", name);
    cmd.env_remove("QT_QPA_PLATFORMTHEME");
    cmd.env(THEME_MARKER, GTK3);
}

// Give a program Flea opens the platform theme this launcher traded away, and nothing else.
pub fn restore_platform_theme(command: &mut Command) {
    apply_theme_restore(command, std::env::var_os(THEME_MARKER).as_deref());
}

// Split from restore_platform_theme so a test can drive it without this process's environment.
fn apply_theme_restore(command: &mut Command, marker: Option<&OsStr>) {
    let Some(theme) = marker.filter(|value| !value.is_empty()) else {
        return;
    };
    command.env("QT_QPA_PLATFORMTHEME", theme);
    command.env_remove("QS_ICON_THEME");
    command.env_remove(THEME_MARKER);
}

fn exec(mut cmd: Command) -> i32 {
    // The setting is preserved across exec, so this is the last point that can hand it to qs.
    thp::disable();
    // exec() only returns on failure; the reason is elided, never shown raw.
    let _ = cmd.exec();
    eprintln!("flea: could not start the shell, qs is not on PATH or failed to run");
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    // Command keeps its overrides rather than a rendered environment, so this reads back what was set.
    fn override_of(cmd: &Command, key: &str) -> Option<String> {
        cmd.get_envs()
            .find(|(name, _)| *name == OsStr::new(key))
            .and_then(|(_, value)| value)
            .map(|value| value.to_string_lossy().into_owned())
    }

    #[test]
    fn a_display_gpu_pin_sets_both_loader_variables() {
        let icd = String::from("/usr/share/vulkan/icd.d/nvidia_icd.json");
        let mut cmd = Command::new("true");
        apply_display_pin(&mut cmd, vulkan::DisplayPin::Pin { icd: icd.clone(), gpu: (0x10de, 0x27e0) });
        assert_eq!(override_of(&cmd, "VK_DRIVER_FILES").as_deref(), Some(icd.as_str()));
        assert_eq!(override_of(&cmd, "VK_ICD_FILENAMES").as_deref(), Some(icd.as_str()));
    }

    #[test]
    fn a_pin_marks_itself_so_a_child_can_tell_it_from_the_operators_own_list() {
        let mut cmd = Command::new("true");
        apply_display_pin(&mut cmd, vulkan::DisplayPin::Pin { icd: String::from("/x.json"), gpu: (0x10de, 0x27e0) });
        assert_eq!(override_of(&cmd, vulkan::PIN_MARKER).as_deref(), Some("1"));
    }

    #[test]
    fn an_exported_but_empty_loader_variable_is_absent_not_a_choice() {
        assert!(!operator_chose_icd(None, None));
        assert!(!operator_chose_icd(Some(OsStr::new("")), Some(OsStr::new(""))));
        assert!(operator_chose_icd(Some(OsStr::new("/a.json")), None));
        assert!(operator_chose_icd(None, Some(OsStr::new("/b.json"))));
    }

    #[test]
    fn a_box_needing_no_pin_sets_no_loader_variable() {
        let mut cmd = Command::new("true");
        apply_display_pin(&mut cmd, vulkan::DisplayPin::NotNeeded);
        assert_eq!(override_of(&cmd, "VK_DRIVER_FILES"), None);
        assert_eq!(override_of(&cmd, "VK_ICD_FILENAMES"), None);
        assert_eq!(override_of(&cmd, vulkan::PIN_MARKER), None);
    }

    // A removal is a present key with no value, which override_of cannot tell from an absent one.
    fn removed(cmd: &Command, key: &str) -> bool {
        cmd.get_envs().any(|(name, value)| name == OsStr::new(key) && value.is_none())
    }

    #[test]
    fn a_traded_platform_theme_is_handed_back_to_an_opened_program() {
        let mut cmd = Command::new("true");
        apply_theme_restore(&mut cmd, Some(OsStr::new("gtk3")));
        assert_eq!(override_of(&cmd, "QT_QPA_PLATFORMTHEME").as_deref(), Some("gtk3"));
        assert!(removed(&cmd, "QS_ICON_THEME"));
        assert!(removed(&cmd, THEME_MARKER));
    }

    #[test]
    fn an_unmarked_launch_leaves_an_opened_programs_theme_alone() {
        let mut cmd = Command::new("true");
        apply_theme_restore(&mut cmd, None);
        assert_eq!(cmd.get_envs().count(), 0);
    }

    #[test]
    fn an_exported_but_empty_theme_marker_is_absent_not_a_trade() {
        let mut cmd = Command::new("true");
        apply_theme_restore(&mut cmd, Some(OsStr::new("")));
        assert_eq!(cmd.get_envs().count(), 0);
    }

    #[test]
    fn a_display_gpu_with_no_icd_file_sets_no_loader_variable() {
        let mut cmd = Command::new("true");
        apply_display_pin(&mut cmd, vulkan::DisplayPin::Unmatched { vendor: 0x10de });
        assert_eq!(override_of(&cmd, "VK_DRIVER_FILES"), None);
        assert_eq!(override_of(&cmd, "VK_ICD_FILENAMES"), None);
    }
}
