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

use commands::{capture_all_monitors, capture_once, capture_region, save_edited_image};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_screenshots::init())
        .invoke_handler(tauri::generate_handler![
            capture_once,
            capture_all_monitors,
            capture_region,
            save_edited_image
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
