//! BetterShot - A screenshot capture and editing application
//!
//! This crate provides the Tauri backend for capturing, editing,
//! and saving screenshots with various features like region selection
//! and background customization.

mod clipboard;
mod commands;
mod image;
mod screenshot;
mod utils;

use commands::{
    capture_all_monitors, capture_once, capture_region, get_desktop_directory, get_mouse_position,
    get_temp_directory, native_capture_fullscreen, native_capture_interactive,
    native_capture_window, play_screenshot_sound, save_edited_image,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_screenshots::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .setup(|app| {
            use tauri::Manager;

            if let Some(window) = app.get_webview_window("main") {
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

            use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem};

            let open_item = MenuItemBuilder::with_id("open", "Open Better Shot").build(app)?;

            let capture_region_item =
                MenuItemBuilder::with_id("capture_region", "Capture Region").build(app)?;

            let capture_screen_item =
                MenuItemBuilder::with_id("capture_screen", "Capture Screen").build(app)?;

            let capture_window_item =
                MenuItemBuilder::with_id("capture_window", "Capture Window").build(app)?;

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
                    &PredefinedMenuItem::separator(app)?,
                    &quit_item,
                ])
                .build()?;

            let _tray = tauri::tray::TrayIconBuilder::new()
                .menu(&menu)
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Better Shot")
                .on_menu_event(move |app, event| {
                    use tauri::{Emitter, Manager};
                    match event.id().as_ref() {
                        "open" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.set_focus();
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
            play_screenshot_sound,
            get_mouse_position
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
