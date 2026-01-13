//! Clipboard operations module

use crate::utils::AppResult;

/// Copy an image file to the system clipboard
/// Uses platform-specific methods for each OS
pub fn copy_image_to_clipboard(image_path: &str) -> AppResult<()> {
    #[cfg(target_os = "macos")]
    {
        copy_image_to_clipboard_macos(image_path)
    }

    #[cfg(target_os = "windows")]
    {
        copy_image_to_clipboard_windows(image_path)
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err(format!("Clipboard copy not supported on this platform"))
    }
}

/// Copy an image file to the system clipboard using macOS native APIs
/// This approach works with clipboard managers like Raycast
#[cfg(target_os = "macos")]
fn copy_image_to_clipboard_macos(image_path: &str) -> AppResult<()> {
    use std::process::Command;

    // Use osascript to copy the image file to clipboard
    // This method properly integrates with macOS clipboard and clipboard managers
    let script = format!(
        r#"set the clipboard to (read (POSIX file "{}") as «class PNGf»)"#,
        image_path
    );

    let output = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .output()
        .map_err(|e| format!("Failed to execute osascript: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Failed to copy image to clipboard: {}", stderr));
    }

    Ok(())
}

/// Copy an image file to the system clipboard using Windows APIs via PowerShell
#[cfg(target_os = "windows")]
fn copy_image_to_clipboard_windows(image_path: &str) -> AppResult<()> {
    use std::path::Path;
    use std::process::Command;

    // Validate that the file exists and is a regular file
    let path = Path::new(image_path);
    if !path.exists() {
        return Err(format!("File not found: {}", image_path));
    }
    if !path.is_file() {
        return Err(format!("Path is not a file: {}", image_path));
    }

    // Get the canonical path to ensure it's a valid, absolute path
    let canonical_path = path
        .canonicalize()
        .map_err(|e| format!("Failed to resolve path: {}", e))?;
    let path_str = canonical_path.to_string_lossy();

    // Use PowerShell to copy the image to clipboard
    // This uses .NET's System.Windows.Forms.Clipboard class
    // Escape single quotes for PowerShell string literal
    let escaped_path = path_str.replace("'", "''");
    let script = format!(
        r#"Add-Type -AssemblyName System.Windows.Forms; $image = [System.Drawing.Image]::FromFile('{}'); [System.Windows.Forms.Clipboard]::SetImage($image); $image.Dispose()"#,
        escaped_path
    );

    let output = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .output()
        .map_err(|e| format!("Failed to execute PowerShell: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Failed to copy image to clipboard: {}", stderr));
    }

    Ok(())
}
