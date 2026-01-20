//! BetterShot - A screenshot capture and editing application
//!
//! This crate provides the Tauri backend for capturing, editing,
//! and saving screenshots with various features like region selection
//! and background customization.

mod clipboard;
mod commands;
mod image;
mod ocr;
mod screenshot;
mod utils;

use commands::{
    capture_all_monitors, capture_once, capture_region, get_desktop_directory, get_mouse_position,
    get_temp_directory, move_window_to_active_space, native_capture_fullscreen,
    native_capture_interactive, native_capture_window, native_capture_ocr_region,
    play_screenshot_sound, save_edited_image,
};

use tauri::{Emitter, Manager, WebviewUrl, WebviewWindowBuilder};

/// Sets the app to be an "accessory" application on macOS.
/// This hides the Dock icon and removes the app from Cmd+Tab.
#[cfg(target_os = "macos")]
fn set_macos_accessory_mode() {
    use objc2::{MainThreadMarker};
    use objc2_app_kit::{NSApp, NSApplicationActivationPolicy};

    let mtm = MainThreadMarker::new().unwrap();
    let app = NSApp(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);
}

/// Shows the main application window (creates it if needed, shows if hidden)
fn show_main_window(app: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(window) = app.get_webview_window("main") {
        // Window exists, just show and focus it
        let _ = window.show();
        let _ = window.set_focus();
    } else {
        // Create new window (shouldn't happen normally as we create on startup)
        let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
            .title("Better Shot")
            .inner_size(1200.0, 800.0)
            .min_inner_size(800.0, 600.0)
            .center()
            .resizable(true)
            .decorations(true)
            .build()?;

        // Handle close request - hide instead of quit
        let window_clone = window.clone();
        window.on_window_event(move |event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if let Err(e) = window_clone.hide() {
                    eprintln!("Failed to hide window: {}", e);
                }
                api.prevent_close();
            }
        });
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_screenshots::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--hidden"]),
        ))
        .setup(|app| {
            use tauri::menu::{ MenuBuilder, MenuItemBuilder, PredefinedMenuItem};

            // Set accessory mode on macOS to hide Dock icon and Cmd+Tab entry
            #[cfg(target_os = "macos")]
            set_macos_accessory_mode();

            // Enable autostart by default (user can disable in settings)
            #[cfg(target_os = "macos")]
            {
                use tauri_plugin_autostart::ManagerExt;
                let autostart_manager = app.autolaunch();
                // Only enable if not already enabled (don't override user preference)
                if !autostart_manager.is_enabled().unwrap_or(false) {
                    let _ = autostart_manager.enable();
                }
            }

            // Create the main window but keep it hidden initially
            // This allows the React frontend to run and set up event listeners
            let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                .title("Better Shot")
                .inner_size(1200.0, 800.0)
                .min_inner_size(800.0, 600.0)
                .center()
                .resizable(true)
                .decorations(true)
                .visible(false) // Start hidden
                .build()?;

            // Handle close request - hide instead of quit
            let window_clone = window.clone();
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    if let Err(e) = window_clone.hide() {
                        eprintln!("Failed to hide window: {}", e);
                    }
                    api.prevent_close();
                }
            });

            let open_item = MenuItemBuilder::with_id("open", "Open Better Shot").build(app)?;

            let capture_region_item =
                MenuItemBuilder::with_id("capture_region", "Capture Region").build(app)?;

            let capture_screen_item =
                MenuItemBuilder::with_id("capture_screen", "Capture Screen").build(app)?;

            let capture_window_item =
                MenuItemBuilder::with_id("capture_window", "Capture Window").build(app)?;

            let capture_ocr_item =
                MenuItemBuilder::with_id("capture_ocr", "OCR Region").build(app)?;

            let preferences_item =
                MenuItemBuilder::with_id("preferences", "Preferences...")
                    .accelerator("CommandOrControl+,")
                    .build(app)?;

            let quit_item = MenuItemBuilder::with_id("quit", "Quit")
                .accelerator("CommandOrControl+Q")
                .build(app)?;

            let menu = MenuBuilder::new(app)
                .items(&[
                    &open_item,
                    &PredefinedMenuItem::separator(app)?,
                    &capture_region_item,
                    &capture_screen_item,
                    &capture_window_item,
                    &capture_ocr_item,
                    &PredefinedMenuItem::separator(app)?,
                    &preferences_item,
                    &PredefinedMenuItem::separator(app)?,
                    &quit_item,
                ])
                .build()?;
            let _tray = tauri::tray::TrayIconBuilder::new()
                .menu(&menu)
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Better Shot")
                .on_menu_event(move |app, event| {
                    match event.id().as_ref() {
                        "open" => {
                            if let Err(e) = show_main_window(app) {
                                eprintln!("Failed to show window: {}", e);
                            }
                        }
                        "capture_region" => {
                            let _ = app.emit("capture-triggered", ());
                        }
                        "capture_screen" => {
                            let _ = app.emit("capture-fullscreen", ());
                        }
                        "capture_window" => {
                            let _ = app.emit("capture-window", ());
                        }
                        "capture_ocr" => {
                            let _ = app.emit("capture-ocr", ());
                        }
                        "preferences" => {
                            if let Err(e) = show_main_window(app) {
                                eprintln!("Failed to show window: {}", e);
                            } else {
                                let _ = app.emit("open-preferences", ());
                            }
                        }
                        "quit" => {
                            app.exit(0);
                        }
                        _ => {}
                    }
                })
                .build(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            capture_once,
            capture_all_monitors,
            capture_region,
            save_edited_image,
            get_desktop_directory,
            get_temp_directory,
            native_capture_interactive,
            native_capture_fullscreen,
            native_capture_window,
            native_capture_ocr_region,
            play_screenshot_sound,
            get_mouse_position,
            move_window_to_active_space
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
