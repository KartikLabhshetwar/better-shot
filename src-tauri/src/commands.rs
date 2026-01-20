//! Tauri commands module

use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

#[cfg(target_os = "macos")]
use objc2::msg_send;
use objc2_app_kit::NSWindow;

use crate::clipboard::{copy_image_to_clipboard, copy_text_to_clipboard};
use crate::image::{copy_screenshot_to_dir, crop_image, save_base64_image, CropRegion};
use crate::ocr::recognize_text_from_image;
use crate::screenshot::{
    capture_all_monitors as capture_monitors, capture_primary_monitor, MonitorShot,
};
use crate::utils::{generate_filename, get_desktop_path};

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

/// Play the macOS screenshot sound using CoreAudio
/// This uses AudioServicesPlaySystemSound which is non-blocking and works
/// even when other audio/video is playing. Falls back to osascript if CoreAudio fails.
#[tauri::command]
pub async fn play_screenshot_sound() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        use objc2_audio_toolbox::{
            AudioServicesCreateSystemSoundID, AudioServicesDisposeSystemSoundID,
            AudioServicesPlaySystemSound, SystemSoundID,
        };
        use objc2_core_foundation::{CFString, CFURL, CFURLPathStyle};
        use std::ptr::NonNull;

        let sound_path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif";

        std::thread::spawn(move || {
            let cfstr = CFString::from_str(sound_path);
            let url = match CFURL::with_file_system_path(None, Some(&cfstr), CFURLPathStyle::CFURLPOSIXPathStyle, false) {
                Some(url) => url,
                None => {
                    fallback_sound_playback();
                    return;
                }
            };

            let mut sound_id: SystemSoundID = 0;
            let status = unsafe {
                AudioServicesCreateSystemSoundID(
                    &url,
                    NonNull::new(&mut sound_id).unwrap(),
                )
            };

            if status != 0 {
                fallback_sound_playback();
                return;
            }

            unsafe {
                AudioServicesPlaySystemSound(sound_id);
            }

            std::thread::sleep(std::time::Duration::from_millis(1000));

            unsafe {
                AudioServicesDisposeSystemSoundID(sound_id);
            }
        });
    }

    #[cfg(not(target_os = "macos"))]
    {
        eprintln!("play_screenshot_sound is only supported on macOS");
    }

    Ok(())
}

#[cfg(target_os = "macos")]
fn fallback_sound_playback() {
    let sound_path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif";
    
    let _ = Command::new("osascript")
        .arg("-e")
        .arg(format!("do shell script \"afplay '{}' &\"", sound_path))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
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

/// Capture region and perform OCR, copying text to clipboard
#[tauri::command]
pub async fn native_capture_ocr_region(save_dir: String) -> Result<String, String> {
    {
        let _lock = SCREENCAPTURE_LOCK
            .lock()
            .map_err(|e| format!("Failed to acquire lock: {}", e))?;

        if is_screencapture_running() {
            return Err("Another screenshot capture is already in progress".to_string());
        }

        check_and_activate_permission().map_err(|e| {
            format!("Permission check failed: {}. Please ensure Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording.", e)
        })?;
    }

    let filename = generate_filename("ocr_temp", "png")?;
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

    if !screenshot_path.exists() {
        return Err("Screenshot was cancelled or failed".to_string());
    }

    play_screenshot_sound().await.ok();

    let recognized_text = recognize_text_from_image(&path_str)
        .map_err(|e| format!("OCR failed: {}", e))?;

    copy_text_to_clipboard(&recognized_text)
        .map_err(|e| format!("Failed to copy text to clipboard: {}", e))?;

    let _ = std::fs::remove_file(&screenshot_path);

    Ok(recognized_text)
}
