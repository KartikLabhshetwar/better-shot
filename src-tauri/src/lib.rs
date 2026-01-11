use arboard::Clipboard;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::AppHandle;

fn copy_image_to_clipboard(image_path: &str) -> Result<(), String> {
    let img = image::open(image_path).map_err(|e| format!("Failed to open image: {}", e))?;

    let rgba_img = img.to_rgba8();
    let width = rgba_img.width() as usize;
    let height = rgba_img.height() as usize;
    let mut rgba_data = Vec::with_capacity(width * height * 4);

    for pixel in rgba_img.pixels() {
        rgba_data.push(pixel[0]);
        rgba_data.push(pixel[1]);
        rgba_data.push(pixel[2]);
        rgba_data.push(pixel[3]);
    }

    let mut clipboard =
        Clipboard::new().map_err(|e| format!("Failed to initialize clipboard: {}", e))?;
    clipboard
        .set_image(arboard::ImageData {
            width,
            height,
            bytes: rgba_data.into(),
        })
        .map_err(|e| format!("Failed to copy to clipboard: {}", e))?;

    Ok(())
}

fn move_screenshot_to_dir(screenshot_path: &str, save_dir: &str) -> Result<String, String> {
    let src_path = PathBuf::from(screenshot_path);
    if !src_path.exists() {
        return Err(format!("Screenshot file not found: {}", screenshot_path));
    }

    let mut dest_dir = PathBuf::from(save_dir);
    fs::create_dir_all(&dest_dir).map_err(|e| format!("Failed to create directory: {}", e))?;

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("Failed to get timestamp: {}", e))?
        .as_secs();

    let filename = format!("shot_{}.png", timestamp);
    dest_dir.push(&filename);

    fs::copy(&src_path, &dest_dir).map_err(|e| format!("Failed to copy screenshot: {}", e))?;

    Ok(dest_dir.to_string_lossy().into_owned())
}

#[tauri::command]
async fn capture_once(
    app_handle: AppHandle,
    save_dir: String,
    copy_to_clip: bool,
) -> Result<String, String> {
    use tauri_plugin_screenshots::{get_monitor_screenshot, get_screenshotable_monitors};

    let monitors = get_screenshotable_monitors()
        .await
        .map_err(|e| format!("Failed to get monitors: {}", e))?;

    if monitors.is_empty() {
        return Err("No monitors available".into());
    }

    let primary_monitor = monitors.first().ok_or("No monitor found")?;

    let screenshot_path = get_monitor_screenshot(app_handle, primary_monitor.id)
        .await
        .map_err(|e| format!("Failed to capture screenshot: {}", e))?;

    let screenshot_path_str = screenshot_path.to_string_lossy().to_string();

    let saved_path = move_screenshot_to_dir(&screenshot_path_str, &save_dir)?;

    if copy_to_clip {
        copy_image_to_clipboard(&saved_path)?;
    }

    Ok(saved_path)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_screenshots::init())
        .invoke_handler(tauri::generate_handler![capture_once])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
