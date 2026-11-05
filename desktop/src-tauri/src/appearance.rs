use crate::native_policy::{Appearance, AppearanceTheme};
use tauri::{window::Color, WebviewWindow};

/// Use the OS compositor, not a web blur loop. Keep caption buttons and hit testing native.
pub fn apply(window: &WebviewWindow, appearance: Appearance, enabled: bool) -> bool {
    let dark = appearance.theme == AppearanceTheme::Dark;
    let _ = window.set_theme(Some(if dark {
        tauri::Theme::Dark
    } else {
        tauri::Theme::Light
    }));
    let requested = enabled && appearance.transparency && supported();
    #[cfg(windows)]
    let active = window.hwnd().is_ok_and(|raw| {
        set_backdrop(
            windows::Win32::Foundation::HWND(raw.0 as *mut _),
            dark,
            requested,
        )
    });
    #[cfg(not(windows))]
    let active = requested;
    let background = if active {
        Color(0, 0, 0, 0)
    } else if dark {
        Color(21, 23, 28, 255)
    } else {
        Color(255, 255, 255, 255)
    };
    let _ = window.set_background_color(Some(background));
    #[cfg(windows)]
    if let Ok(raw) = window.hwnd() {
        use windows::Win32::{Foundation::HWND, Graphics::Dwm::*};
        let caption = caption_color(dark, active);
        let border = DWMWA_COLOR_DEFAULT;
        let text: u32 = if !active {
            DWMWA_COLOR_DEFAULT
        } else if dark {
            0x00f8f8f8
        } else {
            0x00171717
        };
        // Blend the native caption into Mica instead of painting the user's accent strip.
        unsafe {
            let hwnd = HWND(raw.0 as *mut _);
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_CAPTION_COLOR,
                (&caption as *const u32).cast(),
                4,
            );
            let _ =
                DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, (&border as *const u32).cast(), 4);
            let _ = DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR, (&text as *const u32).cast(), 4);
        }
    }
    active
}

#[cfg(windows)]
fn caption_color(dark: bool, active: bool) -> u32 {
    if active {
        0xfffffffe // DWMWA_COLOR_NONE lets the Mica material show through.
    } else if dark {
        0x001c1715 // COLORREF is BGR: match the solid WebView background.
    } else {
        0x00ffffff
    }
}

#[cfg(windows)]
fn set_backdrop(hwnd: windows::Win32::Foundation::HWND, dark: bool, requested: bool) -> bool {
    use windows::Win32::Graphics::Dwm::*;
    let dark = u32::from(dark);
    let backdrop = if requested {
        DWMSBT_MAINWINDOW
    } else {
        DWMSBT_NONE
    };
    unsafe {
        let theme = DwmSetWindowAttribute(
            hwnd,
            DWMWA_USE_IMMERSIVE_DARK_MODE,
            (&dark as *const u32).cast(),
            4,
        );
        let applied = DwmSetWindowAttribute(
            hwnd,
            DWMWA_SYSTEMBACKDROP_TYPE,
            (&backdrop as *const DWM_SYSTEMBACKDROP_TYPE).cast(),
            4,
        );
        let mut actual = DWMSBT_NONE;
        let verified = DwmGetWindowAttribute(
            hwnd,
            DWMWA_SYSTEMBACKDROP_TYPE,
            (&mut actual as *mut DWM_SYSTEMBACKDROP_TYPE).cast(),
            4,
        );
        let active = requested
            && theme.is_ok()
            && applied.is_ok()
            && verified.is_ok()
            && actual == DWMSBT_MAINWINDOW;
        if requested && !active {
            let none = DWMSBT_NONE;
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_SYSTEMBACKDROP_TYPE,
                (&none as *const DWM_SYSTEMBACKDROP_TYPE).cast(),
                4,
            );
        }
        active
    }
}

#[cfg(all(test, windows))]
mod tests {
    #[test]
    fn caption_matches_material_or_solid_theme_instead_of_system_accent() {
        assert_eq!(super::caption_color(true, true), 0xfffffffe);
        assert_eq!(super::caption_color(false, true), 0xfffffffe);
        assert_eq!(super::caption_color(true, false), 0x001c1715);
        assert_eq!(super::caption_color(false, false), 0x00ffffff);
    }

    #[test]
    fn a_rejected_native_backdrop_never_enables_web_transparency() {
        assert!(!super::set_backdrop(
            windows::Win32::Foundation::HWND::default(),
            true,
            true
        ));
    }
}

#[cfg(windows)]
fn supported() -> bool {
    use windows_registry::{CURRENT_USER, LOCAL_MACHINE};
    let build = LOCAL_MACHINE
        .open("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion")
        .and_then(|key| key.get_string("CurrentBuildNumber"))
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(0);
    let transparency = CURRENT_USER
        .open("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize")
        .and_then(|key| key.get_u32("EnableTransparency"))
        .unwrap_or(1)
        != 0;
    let contrast = CURRENT_USER
        .open("Control Panel\\Accessibility\\HighContrast")
        .and_then(|key| key.get_string("Flags"))
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(0)
        & 1
        != 0;
    let mut power = windows::Win32::System::Power::SYSTEM_POWER_STATUS::default();
    let saving = unsafe { windows::Win32::System::Power::GetSystemPowerStatus(&mut power) }.is_ok()
        && power.SystemStatusFlag == 1;
    // The documented, verifiable system backdrop API requires Windows 11 22H2.
    build >= 22621 && transparency && !contrast && !saving
}

#[cfg(not(windows))]
fn supported() -> bool {
    false
}
