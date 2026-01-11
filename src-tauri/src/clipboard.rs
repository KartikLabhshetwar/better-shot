//! Clipboard operations module

use crate::utils::AppResult;
use arboard::Clipboard;

/// Copy an image file to the system clipboard
pub fn copy_image_to_clipboard(image_path: &str) -> AppResult<()> {
    let img = image::open(image_path).map_err(|e| format!("Failed to open image: {}", e))?;

    let rgba_img = img.to_rgba8();
    let width = rgba_img.width() as usize;
    let height = rgba_img.height() as usize;

    // Convert to raw RGBA bytes
    let rgba_data: Vec<u8> = rgba_img.pixels().flat_map(|pixel| pixel.0).collect();

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
