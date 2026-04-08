//! Tauri commands module

use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Manager};

#[cfg(target_os = "macos")]
use objc2::msg_send;
use objc2_app_kit::NSWindow;

use crate::clipboard::copy_image_to_clipboard;
use crate::image::{copy_screenshot_to_dir, crop_image, save_base64_image, CropRegion};
use crate::screenshot::{
    capture_all_monitors as capture_monitors, capture_primary_monitor, MonitorShot,
};
use crate::utils::{ensure_dir, generate_filename, get_desktop_path};
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;

static SCREENCAPTURE_LOCK: Mutex<()> = Mutex::new(());

#[tauri::command]
pub async fn move_window_to_active_space(app_handle: AppHandle) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let window = app_handle
            .get_webview_window("main")
            .ok_or("Main window not found")?;

        window
            .with_webview(|webview| {
                let ns_window = webview.ns_window();
                if ns_window.is_null() {
                    return;
                }
                let ns_window = unsafe { &*ns_window.cast::<NSWindow>() };
                let current: usize = unsafe { msg_send![ns_window, collectionBehavior] };
                let move_to_active_space: usize = 1 << 1;
                let new_behavior = current | move_to_active_space;
                let _: () = unsafe { msg_send![ns_window, setCollectionBehavior: new_behavior] };
                let _: () = unsafe { msg_send![ns_window, orderFrontRegardless] };
            })
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

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
    let region = CropRegion {
        x,
        y,
        width,
        height,
    };
    crop_image(&screenshot_path, region, &save_dir)
}

/// Save an edited image from base64 data
#[tauri::command]
pub async fn save_edited_image(
    image_data: String,
    save_dir: String,
    copy_to_clip: bool,
    prefix: Option<String>,
    filename: Option<String>,
) -> Result<String, String> {
    let chosen_prefix = prefix.unwrap_or_else(|| "bettershot".to_string());

    let saved_path = if let Some(name) = filename {
        // honor custom filename; append .png if needed
        let mut final_name = name.trim().to_string();
        if final_name.is_empty() {
            save_base64_image(&image_data, &save_dir, &chosen_prefix)?
        } else {
            if !final_name.to_lowercase().ends_with(".png") {
                final_name.push_str(".png");
            }
            let dest_path = PathBuf::from(&save_dir);
            ensure_dir(&dest_path).map_err(|e| e)?;
            let file_path = dest_path.join(final_name);
            let base64_data = image_data
                .strip_prefix("data:image/png;base64,")
                .ok_or("Invalid image data format: expected data:image/png;base64, prefix")?;
            let image_bytes = BASE64_STANDARD
                .decode(base64_data)
                .map_err(|e| format!("Failed to decode base64: {}", e))?;
            std::fs::write(&file_path, image_bytes)
                .map_err(|e| format!("Failed to save image: {}", e))?;
            file_path
                .to_str()
                .map(|s| s.to_string())
                .ok_or_else(|| "Failed to convert file path to string".to_string())?
        }
    } else {
        save_base64_image(&image_data, &save_dir, &chosen_prefix)?
    };

    if copy_to_clip {
        copy_image_to_clipboard(&saved_path)?;
    }

    Ok(saved_path)
}

/// Get the user's Desktop directory path (cross-platform)
#[tauri::command]
pub async fn get_desktop_directory() -> Result<String, String> {
    get_desktop_path()
}

/// Get the system temp directory path (cross-platform)
/// Returns the canonical/resolved path to avoid symlink issues
#[tauri::command]
pub async fn get_temp_directory() -> Result<String, String> {
    let temp_dir = std::env::temp_dir();
    // Canonicalize to resolve symlinks (e.g., /tmp -> /private/tmp on macOS)
    let canonical = temp_dir.canonicalize().unwrap_or(temp_dir);
    canonical
        .to_str()
        .map(|s| s.to_string())
        .ok_or_else(|| "Failed to convert temp directory path to string".to_string())
}

/// Check if screencapture is already running
fn is_screencapture_running() -> bool {
    let output = Command::new("pgrep")
        .arg("-x")
        .arg("screencapture")
        .output();

    match output {
        Ok(o) => o.status.success(),
        Err(_) => false,
    }
}

/// Check screen recording permission by attempting a minimal test
/// This helps macOS recognize the permission is already granted
fn check_and_activate_permission() -> Result<(), String> {
    let test_path = std::env::temp_dir().join(format!("bs_test_{}.png", std::process::id()));

    let output = Command::new("screencapture")
        .arg("-x")
        .arg("-T")
        .arg("0")
        .arg(&test_path)
        .stderr(Stdio::piped())
        .stdout(Stdio::piped())
        .output();

    match output {
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            let _ = std::fs::remove_file(&test_path);

            if stderr.contains("permission")
                || stderr.contains("denied")
                || stderr.contains("not authorized")
            {
                return Err("Screen Recording permission not granted".to_string());
            }

            Ok(())
        }
        Err(e) => {
            let err_msg = e.to_string();
            if err_msg.contains("permission")
                || err_msg.contains("denied")
                || err_msg.contains("not authorized")
            {
                Err("Screen Recording permission not granted".to_string())
            } else {
                Ok(())
            }
        }
    }
}

/// Capture screenshot using macOS native screencapture with interactive selection
/// This properly handles Screen Recording permissions through the system
#[tauri::command]
pub async fn native_capture_interactive(save_dir: String) -> Result<String, String> {
    let _lock = SCREENCAPTURE_LOCK
        .lock()
        .map_err(|e| format!("Failed to acquire lock: {}", e))?;

    if is_screencapture_running() {
        return Err("Another screenshot capture is already in progress".to_string());
    }

    check_and_activate_permission().map_err(|e| {
        format!("Permission check failed: {}. Please ensure Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording.", e)
    })?;

    let filename = generate_filename("screenshot", "png")?;
    let save_path = PathBuf::from(&save_dir);
    let screenshot_path = save_path.join(&filename);
    let path_str = screenshot_path.to_string_lossy().to_string();

    let child = Command::new("screencapture")
        .arg("-i")
        .arg("-x")
        .arg(&path_str)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to run screencapture: {}", e))?;

    let output = child
        .wait_with_output()
        .map_err(|e| format!("Failed to wait for screencapture: {}", e))?;

    if !output.status.success() {
        if screenshot_path.exists() {
            let _ = std::fs::remove_file(&screenshot_path);
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.contains("permission")
            || stderr.contains("denied")
            || stderr.contains("not authorized")
        {
            return Err("Screen Recording permission required. Please grant permission in System Settings > Privacy & Security > Screen Recording and restart the app.".to_string());
        }
        return Err("Screenshot was cancelled or failed".to_string());
    }

    if screenshot_path.exists() {
        Ok(path_str)
    } else {
        Err("Screenshot was cancelled or failed".to_string())
    }
}

/// Capture full screen using macOS native screencapture
#[tauri::command]
pub async fn native_capture_fullscreen(save_dir: String) -> Result<String, String> {
    let _lock = SCREENCAPTURE_LOCK
        .lock()
        .map_err(|e| format!("Failed to acquire lock: {}", e))?;

    if is_screencapture_running() {
        return Err("Another screenshot capture is already in progress".to_string());
    }

    check_and_activate_permission().map_err(|e| {
        format!("Permission check failed: {}. Please ensure Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording.", e)
    })?;

    let filename = generate_filename("screenshot", "png")?;
    let save_path = PathBuf::from(&save_dir);
    let screenshot_path = save_path.join(&filename);
    let path_str = screenshot_path.to_string_lossy().to_string();

    let status = Command::new("screencapture")
        .arg("-x")
        .arg(&path_str)
        .status()
        .map_err(|e| format!("Failed to run screencapture: {}", e))?;

    if !status.success() {
        return Err("Screenshot failed".to_string());
    }

    if screenshot_path.exists() {
        Ok(path_str)
    } else {
        Err("Screenshot failed".to_string())
    }
}

/// Play the macOS screenshot sound
#[tauri::command]
pub async fn play_screenshot_sound() -> Result<(), String> {
    // macOS system screenshot sound path
    let sound_path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif";

    // Use afplay to play the sound asynchronously (non-blocking)
    std::thread::spawn(move || {
        let _ = Command::new("afplay")
            .arg(sound_path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    });

    Ok(())
}

#[tauri::command]
pub fn select_directory_dialog(default_path: Option<String>) -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        let mut script = String::from("try\n");
        script.push_str("  set chosen to choose folder with prompt \"Select save directory\"");
        if let Some(path) = default_path {
            let escaped = path.replace('"', "\\\"");
            script.push(' ');
            script.push_str(&format!("default location POSIX file \"{}\"", escaped));
        }
        script.push_str("\n  return POSIX path of chosen\n");
        script.push_str("on error\n  return \"\"\nend try");

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .map_err(|e| format!("Failed to launch directory picker: {}", e))?;

        if !output.status.success() {
            return Err("Directory picker was cancelled or failed".to_string());
        }

        let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if path.is_empty() {
            Ok(None)
        } else {
            Ok(Some(path))
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        Err("Directory picker is only supported on macOS".to_string())
    }
}

#[tauri::command]
pub fn open_image_file_dialog() -> Result<Option<String>, String> {
    #[cfg(target_os = "macos")]
    {
        let script = r#"try
  set chosen to choose file with prompt "Select a photo to edit" of type {"public.png", "public.jpeg", "public.heic", "public.webp"}
  POSIX path of chosen
on error
  ""
end try"#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .map_err(|e| format!("Failed to launch image picker: {}", e))?;

        if !output.status.success() {
            return Err("Image picker was cancelled or failed".to_string());
        }

        let selected = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if selected.is_empty() {
            Ok(None)
        } else {
            Ok(Some(selected))
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        Err("Image picker is only supported on macOS".to_string())
    }
}

#[tauri::command]
pub fn delete_temp_workspace_file(file_path: String) -> Result<(), String> {
    let path = PathBuf::from(&file_path);
    // Only delete files that are inside the bettershot-uploads temp directory
    let mut expected_dir = std::env::temp_dir();
    expected_dir.push("bettershot-uploads");
    let canonical_path = path
        .canonicalize()
        .map_err(|_| "File not found or already deleted".to_string())?;
    let canonical_dir = expected_dir
        .canonicalize()
        .map_err(|_| "Temp workspace directory not found".to_string())?;
    if !canonical_path.starts_with(&canonical_dir) {
        return Err("Refusing to delete file outside the bettershot-uploads workspace".to_string());
    }
    fs::remove_file(&canonical_path)
        .map_err(|e| format!("Failed to delete temp file: {}", e))
}

#[tauri::command]
pub fn copy_file_to_temp_workspace(source_path: String) -> Result<String, String> {
    let source = PathBuf::from(&source_path);
    // Canonicalize to resolve symlinks and reject path traversal components
    let source = source
        .canonicalize()
        .map_err(|_| "Selected file not found or path is invalid".to_string())?;
    if !source.exists() {
        return Err("Selected file no longer exists".to_string());
    }

    let mut target_dir = std::env::temp_dir();
    target_dir.push("bettershot-uploads");
    fs::create_dir_all(&target_dir)
        .map_err(|e| format!("Failed to prepare temporary folder: {}", e))?;

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("Failed to read system time: {}", e))?;

    let file_name = source
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("photo.png");
    let sanitized = sanitize_filename(file_name);

    let dest_name = format!("{}-{}", timestamp.as_millis(), sanitized);
    let destination = target_dir.join(dest_name);

    fs::copy(&source, &destination)
        .map_err(|e| format!("Failed to copy file: {}", e))?;

    destination
        .to_str()
        .map(|s| s.to_string())
        .ok_or_else(|| "Failed to convert temp path to string".to_string())
}

fn sanitize_filename(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        "photo".to_string()
    } else {
        trimmed
            .chars()
            .map(|c| {
                if c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-') {
                    c
                } else {
                    '_'
                }
            })
            .collect()
    }
}

/// Get the current mouse cursor position (for determining which screen to open editor on)
#[tauri::command]
pub async fn get_mouse_position() -> Result<(f64, f64), String> {
    // Use AppleScript to get mouse position - it's the most reliable cross-version approach
    let output = Command::new("osascript")
        .arg("-e")
        .arg("tell application \"System Events\" to return (get position of mouse)")
        .output()
        .map_err(|e| format!("Failed to get mouse position: {}", e))?;

    if !output.status.success() {
        return Err("Failed to get mouse position".to_string());
    }

    let position_str = String::from_utf8_lossy(&output.stdout);
    let parts: Vec<&str> = position_str.trim().split(", ").collect();

    if parts.len() != 2 {
        return Err("Invalid mouse position format".to_string());
    }

    let x: f64 = parts[0]
        .parse()
        .map_err(|_| "Failed to parse X coordinate")?;
    let y: f64 = parts[1]
        .parse()
        .map_err(|_| "Failed to parse Y coordinate")?;

    Ok((x, y))
}

/// Capture specific window using macOS native screencapture
#[tauri::command]
pub async fn native_capture_window(save_dir: String) -> Result<String, String> {
    let _lock = SCREENCAPTURE_LOCK
        .lock()
        .map_err(|e| format!("Failed to acquire lock: {}", e))?;

    if is_screencapture_running() {
        return Err("Another screenshot capture is already in progress".to_string());
    }

    check_and_activate_permission().map_err(|e| {
        format!("Permission check failed: {}. Please ensure Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording.", e)
    })?;

    let filename = generate_filename("screenshot", "png")?;
    let save_path = PathBuf::from(&save_dir);
    let screenshot_path = save_path.join(&filename);
    let path_str = screenshot_path.to_string_lossy().to_string();

    let child = Command::new("screencapture")
        .arg("-w")
        .arg("-x")
        .arg(&path_str)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to run screencapture: {}", e))?;

    let output = child
        .wait_with_output()
        .map_err(|e| format!("Failed to wait for screencapture: {}", e))?;

    if !output.status.success() {
        if screenshot_path.exists() {
            let _ = std::fs::remove_file(&screenshot_path);
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.contains("permission")
            || stderr.contains("denied")
            || stderr.contains("not authorized")
        {
            return Err("Screen Recording permission required. Please grant permission in System Settings > Privacy & Security > Screen Recording and restart the app.".to_string());
        }
        return Err("Screenshot was cancelled or failed".to_string());
    }

    if screenshot_path.exists() {
        Ok(path_str)
    } else {
        Err("Screenshot was cancelled or failed".to_string())
    }
}
