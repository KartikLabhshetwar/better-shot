//! Tauri commands module

use std::path::PathBuf;
use std::sync::Mutex;
use tauri::AppHandle;

#[cfg(any(target_os = "macos", target_os = "windows"))]
use std::process::{Command, Stdio};

use crate::clipboard::copy_image_to_clipboard;
use crate::image::{copy_screenshot_to_dir, crop_image, save_base64_image, CropRegion};
use crate::screenshot::{
    capture_all_monitors as capture_monitors, capture_primary_monitor, MonitorShot,
};
use crate::utils::{generate_filename, get_desktop_path};

static SCREENCAPTURE_LOCK: Mutex<()> = Mutex::new(());

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
) -> Result<String, String> {
    let saved_path = save_base64_image(&image_data, &save_dir, "bettershot")?;

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

/// Check if screencapture is already running (macOS only)
#[cfg(target_os = "macos")]
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

/// Stub for Windows - always returns false since we use different capture mechanism
#[cfg(target_os = "windows")]
fn is_screencapture_running() -> bool {
    false
}

/// Check screen recording permission by attempting a minimal test (macOS only)
/// This helps macOS recognize the permission is already granted
#[cfg(target_os = "macos")]
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

/// Windows doesn't require special permission checks for screen capture
#[cfg(target_os = "windows")]
fn check_and_activate_permission() -> Result<(), String> {
    Ok(())
}

/// Capture screenshot with interactive selection
/// Uses platform-specific capture mechanisms
#[tauri::command]
pub async fn native_capture_interactive(save_dir: String) -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        native_capture_interactive_macos(save_dir).await
    }

    #[cfg(target_os = "windows")]
    {
        native_capture_interactive_windows(save_dir).await
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err("Interactive capture not supported on this platform".to_string())
    }
}

/// macOS implementation using screencapture
#[cfg(target_os = "macos")]
async fn native_capture_interactive_macos(save_dir: String) -> Result<String, String> {
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

/// Windows implementation using Snipping Tool
#[cfg(target_os = "windows")]
async fn native_capture_interactive_windows(save_dir: String) -> Result<String, String> {
    use xcap::Monitor;

    let _lock = SCREENCAPTURE_LOCK
        .lock()
        .map_err(|e| format!("Failed to acquire lock: {}", e))?;

    // On Windows, we use xcap library for screen capture since Snipping Tool
    // doesn't provide a good programmatic interface.
    // For interactive selection, we capture all monitors and let the frontend handle selection.
    let monitors = Monitor::all().map_err(|e| format!("Failed to get monitors: {}", e))?;

    if monitors.is_empty() {
        return Err("No monitors available".to_string());
    }

    // Capture the primary monitor
    let primary_monitor = &monitors[0];
    let image = primary_monitor
        .capture_image()
        .map_err(|e| format!("Failed to capture screen: {}", e))?;

    let filename = generate_filename("screenshot", "png")?;
    let save_path = PathBuf::from(&save_dir);
    let screenshot_path = save_path.join(&filename);
    let path_str = screenshot_path.to_string_lossy().to_string();

    image
        .save(&screenshot_path)
        .map_err(|e| format!("Failed to save screenshot: {}", e))?;

    Ok(path_str)
}

/// Capture full screen
/// Uses platform-specific capture mechanisms
#[tauri::command]
pub async fn native_capture_fullscreen(save_dir: String) -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        native_capture_fullscreen_macos(save_dir).await
    }

    #[cfg(target_os = "windows")]
    {
        native_capture_fullscreen_windows(save_dir).await
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err("Fullscreen capture not supported on this platform".to_string())
    }
}

/// macOS implementation using screencapture
#[cfg(target_os = "macos")]
async fn native_capture_fullscreen_macos(save_dir: String) -> Result<String, String> {
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

/// Windows implementation using xcap
#[cfg(target_os = "windows")]
async fn native_capture_fullscreen_windows(save_dir: String) -> Result<String, String> {
    use xcap::Monitor;

    let _lock = SCREENCAPTURE_LOCK
        .lock()
        .map_err(|e| format!("Failed to acquire lock: {}", e))?;

    let monitors = Monitor::all().map_err(|e| format!("Failed to get monitors: {}", e))?;

    if monitors.is_empty() {
        return Err("No monitors available".to_string());
    }

    // Capture the primary monitor
    let primary_monitor = &monitors[0];
    let image = primary_monitor
        .capture_image()
        .map_err(|e| format!("Failed to capture screen: {}", e))?;

    let filename = generate_filename("screenshot", "png")?;
    let save_path = PathBuf::from(&save_dir);
    let screenshot_path = save_path.join(&filename);
    let path_str = screenshot_path.to_string_lossy().to_string();

    image
        .save(&screenshot_path)
        .map_err(|e| format!("Failed to save screenshot: {}", e))?;

    Ok(path_str)
}

/// Play the screenshot sound
/// Uses platform-specific sound mechanisms
#[tauri::command]
pub async fn play_screenshot_sound() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
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
    }

    #[cfg(target_os = "windows")]
    {
        // Use PowerShell to play Windows system sound
        std::thread::spawn(move || {
            let _ = Command::new("powershell")
                .args([
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    "[System.Media.SystemSounds]::Asterisk.Play()",
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn();
        });
    }

    Ok(())
}

/// Get the current mouse cursor position (for determining which screen to open editor on)
#[tauri::command]
pub async fn get_mouse_position() -> Result<(f64, f64), String> {
    #[cfg(target_os = "macos")]
    {
        get_mouse_position_macos().await
    }

    #[cfg(target_os = "windows")]
    {
        get_mouse_position_windows().await
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err("Mouse position not supported on this platform".to_string())
    }
}

/// macOS implementation using AppleScript
#[cfg(target_os = "macos")]
async fn get_mouse_position_macos() -> Result<(f64, f64), String> {
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

/// Windows implementation using PowerShell
#[cfg(target_os = "windows")]
async fn get_mouse_position_windows() -> Result<(f64, f64), String> {
    let script = r#"Add-Type -AssemblyName System.Windows.Forms; $pos = [System.Windows.Forms.Cursor]::Position; Write-Output "$($pos.X),$($pos.Y)""#;

    let output = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .output()
        .map_err(|e| format!("Failed to get mouse position: {}", e))?;

    if !output.status.success() {
        return Err("Failed to get mouse position".to_string());
    }

    let position_str = String::from_utf8_lossy(&output.stdout);
    let parts: Vec<&str> = position_str.trim().split(',').collect();

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

/// Capture specific window
/// Uses platform-specific capture mechanisms
#[tauri::command]
pub async fn native_capture_window(save_dir: String) -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        native_capture_window_macos(save_dir).await
    }

    #[cfg(target_os = "windows")]
    {
        native_capture_window_windows(save_dir).await
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err("Window capture not supported on this platform".to_string())
    }
}

/// macOS implementation using screencapture
#[cfg(target_os = "macos")]
async fn native_capture_window_macos(save_dir: String) -> Result<String, String> {
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

/// Windows implementation - falls back to fullscreen capture
/// since programmatic window capture requires more complex Windows APIs
#[cfg(target_os = "windows")]
async fn native_capture_window_windows(save_dir: String) -> Result<String, String> {
    // On Windows, capturing a specific window programmatically is complex
    // Fall back to fullscreen capture and let user crop in the editor
    native_capture_fullscreen_windows(save_dir).await
}
