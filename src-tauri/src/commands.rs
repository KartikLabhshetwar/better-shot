//! Tauri commands module

use tauri::AppHandle;

use crate::clipboard::copy_image_to_clipboard;
use crate::image::{copy_screenshot_to_dir, crop_image, save_base64_image, CropRegion};
use crate::screenshot::{capture_all_monitors as capture_monitors, capture_primary_monitor, MonitorShot};

/// Quick capture of primary monitor
#[tauri::command]
pub async fn capture_once(
    app_handle: AppHandle,
    save_dir: String,
    copy_to_clip: bool,
) -> Result<String, String> {
    let screenshot_path = capture_primary_monitor(app_handle).await?;
    let screenshot_path_str = screenshot_path.to_string_lossy().to_string();
    
    let saved_path = copy_screenshot_to_dir(&screenshot_path_str, &save_dir)?;

    if copy_to_clip {
        copy_image_to_clipboard(&saved_path)?;
    }

    Ok(saved_path)
}

/// Capture all monitors with geometry info
#[tauri::command]
pub async fn capture_all_monitors(
    _app_handle: AppHandle,
    save_dir: String,
) -> Result<Vec<MonitorShot>, String> {
    capture_monitors(&save_dir)
}

/// Crop a region from a screenshot
#[tauri::command]
pub async fn capture_region(
    screenshot_path: String,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    save_dir: String,
) -> Result<String, String> {
    let region = CropRegion { x, y, width, height };
    crop_image(&screenshot_path, region, &save_dir)
}

/// Save an edited image from base64 data
#[tauri::command]
pub async fn save_edited_image(
    image_data: String,
    save_dir: String,
    copy_to_clip: bool,
) -> Result<String, String> {
    let saved_path = save_base64_image(&image_data, &save_dir, "edited")?;

    if copy_to_clip {
        copy_image_to_clipboard(&saved_path)?;
    }

    Ok(saved_path)
}
