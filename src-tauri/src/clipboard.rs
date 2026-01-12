//! Clipboard operations module

use crate::utils::AppResult;
use std::process::Command;

/// Copy an image file to the system clipboard using macOS native APIs
/// This approach works with clipboard managers like Raycast
pub fn copy_image_to_clipboard(image_path: &str) -> AppResult<()> {
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
