#[cfg(windows)]
pub fn register() -> Result<(), Box<dyn std::error::Error>> {
    use std::{os::windows::ffi::OsStrExt, path::PathBuf};
    use windows::{
        core::{Interface, GUID, PCWSTR},
        Win32::{
            Foundation::PROPERTYKEY,
            System::Com::{
                CoCreateInstance, CoInitializeEx, CoUninitialize, IPersistFile,
                CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, STGM_READWRITE,
            },
            UI::Shell::{IShellLinkW, PropertiesSystem::IPropertyStore, ShellLink},
        },
    };
    let path = PathBuf::from(std::env::var_os("APPDATA").ok_or("Missing app data path")?)
        .join("Microsoft/Windows/Start Menu/Programs/KB OneMail.lnk");
    if !path.is_file() {
        return Ok(());
    }
    let wide = path
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    let executable = std::env::current_exe()?;
    let canonical_executable = executable.canonicalize()?;
    let icon_path = executable
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    unsafe {
        CoInitializeEx(None, COINIT_APARTMENTTHREADED).ok()?;
        struct Apartment;
        impl Drop for Apartment {
            fn drop(&mut self) {
                unsafe { CoUninitialize() }
            }
        }
        let _apartment = Apartment;
        let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)?;
        let file: IPersistFile = link.cast()?;
        file.Load(PCWSTR(wide.as_ptr()), STGM_READWRITE)?;
        let mut target = vec![0u16; 32768];
        link.GetPath(&mut target, std::ptr::null_mut(), 0)?;
        let end = target
            .iter()
            .position(|value| *value == 0)
            .ok_or("Invalid shortcut target")?;
        let target = PathBuf::from(String::from_utf16(&target[..end])?).canonicalize()?;
        if target != canonical_executable {
            return Err("The Start menu shortcut belongs to another installation".into());
        }
        // Windows Search gets the app icon from the Start menu shortcut. Tauri's
        // NSIS shortcut has an empty icon location on some installs, so point it
        // explicitly at the executable's embedded branded icon.
        link.SetIconLocation(PCWSTR(icon_path.as_ptr()), 0)?;
        // Protocol-only toasts need a stub CLSID to survive in Notification Center.
        let clsid = GUID::from_u128(0x93b45463_9e1a_4196_9f21_b997f0d344ad);
        let key = PROPERTYKEY {
            fmtid: GUID::from_u128(0x9f4c2855_9f79_4b39_a8d0_e1d42de1d5f3),
            pid: 26,
        };
        let value = owned_clsid(clsid)?;
        let store: IPropertyStore = link.cast()?;
        store.SetValue(&key, &value)?;
        store.Commit()?;
        file.Save(PCWSTR(wide.as_ptr()), true)?;
    }
    Ok(())
}

#[cfg(windows)]
fn owned_clsid(
    clsid: windows::core::GUID,
) -> windows::core::Result<windows::Win32::System::Com::StructuredStorage::PROPVARIANT> {
    use std::mem::{size_of, ManuallyDrop};
    use windows::{
        core::GUID,
        Win32::System::{
            Com::{CoTaskMemAlloc, StructuredStorage::*},
            Variant::VT_CLSID,
        },
    };
    // PROPVARIANT's Drop calls PropVariantClear: the GUID must use the COM allocator.
    let pointer = unsafe { CoTaskMemAlloc(size_of::<GUID>()) }.cast::<GUID>();
    if pointer.is_null() {
        return Err(windows::core::Error::from_hresult(
            windows::Win32::Foundation::E_OUTOFMEMORY,
        ));
    }
    unsafe {
        pointer.write(clsid);
    }
    Ok(PROPVARIANT {
        Anonymous: PROPVARIANT_0 {
            Anonymous: ManuallyDrop::new(PROPVARIANT_0_0 {
                vt: VT_CLSID,
                Anonymous: PROPVARIANT_0_0_0 { puuid: pointer },
                ..Default::default()
            }),
        },
    })
}

#[cfg(all(test, windows))]
mod tests {
    #[test]
    fn notification_clsid_owns_memory_that_the_windows_wrapper_can_clone_and_release() {
        use windows::{core::GUID, Win32::System::Variant::VT_CLSID};
        let expected = GUID::from_u128(0x93b45463_9e1a_4196_9f21_b997f0d344ad);
        for _ in 0..16 {
            let value = super::owned_clsid(expected).unwrap();
            let copy = value.clone();
            drop(value);
            unsafe {
                assert_eq!(copy.Anonymous.Anonymous.vt, VT_CLSID);
                assert_eq!(*copy.Anonymous.Anonymous.Anonymous.puuid, expected);
            }
            drop(copy);
        }
    }
}

#[cfg(not(windows))]
pub fn register() -> Result<(), Box<dyn std::error::Error>> {
    Ok(())
}
