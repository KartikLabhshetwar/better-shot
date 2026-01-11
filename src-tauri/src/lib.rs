use arboard::Clipboard;
use image::{ImageBuffer, Rgba};
use scap::capturer::{Capturer, Options};
use scap::frame::Frame;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

fn check_permissions() -> Result<(), String> {
    if !scap::is_supported() {
        return Err("Platform not supported by scap".into());
    }

    if !scap::has_permission() {
        let granted = scap::request_permission();
        if !granted {
            return Err("Screen recording permission denied".into());
        }
    }

    Ok(())
}

fn convert_bgra_to_rgba(bgra_data: &[u8], width: u32, height: u32) -> Result<ImageBuffer<Rgba<u8>, Vec<u8>>, String> {
    let expected_len = (width * height * 4) as usize;
    if bgra_data.len() != expected_len {
        return Err(format!("Invalid buffer length: expected {}, got {}", expected_len, bgra_data.len()));
    }

    let mut rgba_bytes = Vec::with_capacity(expected_len);

    for chunk in bgra_data.chunks_exact(4) {
        let b = chunk[0];
        let g = chunk[1];
        let r = chunk[2];
        let a = chunk[3];
        rgba_bytes.push(r);
        rgba_bytes.push(g);
        rgba_bytes.push(b);
        rgba_bytes.push(a);
    }

    ImageBuffer::<Rgba<u8>, _>::from_raw(width, height, rgba_bytes)
        .ok_or("Failed to create image buffer".into())
}

fn save_png(img: &ImageBuffer<Rgba<u8>, Vec<u8>>, save_dir: &str) -> Result<String, String> {
    let mut path = PathBuf::from(save_dir);
    fs::create_dir_all(&path).map_err(|e| format!("Failed to create directory: {}", e))?;

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("Failed to get timestamp: {}", e))?
        .as_secs();

    path.push(format!("shot_{}.png", timestamp));

    img.save(&path)
        .map_err(|e| format!("Failed to save image: {}", e))?;

    Ok(path.to_string_lossy().into_owned())
}

fn copy_to_clipboard(img: &ImageBuffer<Rgba<u8>, Vec<u8>>) -> Result<(), String> {
    let width = img.width() as usize;
    let height = img.height() as usize;
    let mut rgba_data = Vec::with_capacity(width * height * 4);

    for pixel in img.pixels() {
        rgba_data.push(pixel[0]);
        rgba_data.push(pixel[1]);
        rgba_data.push(pixel[2]);
        rgba_data.push(pixel[3]);
    }

    let mut clipboard = Clipboard::new().map_err(|e| format!("Failed to initialize clipboard: {}", e))?;
    clipboard
        .set_image(arboard::ImageData {
            width,
            height,
            bytes: rgba_data.into(),
        })
        .map_err(|e| format!("Failed to copy to clipboard: {}", e))?;

    Ok(())
}

#[tauri::command]
fn capture_once(save_dir: String, copy_to_clip: bool) -> Result<String, String> {
    check_permissions()?;

    let options = Options {
        fps: 30,
        target: None,
        show_cursor: true,
        output_type: scap::frame::FrameType::BGRAFrame,
        ..Default::default()
    };

    let mut capturer = Capturer::build(options)
        .map_err(|e| format!("Failed to build capturer: {:?}", e))?;

    capturer.start_capture();

    let frame: Frame = capturer
        .next_frame()
        .ok_or("No frame captured")?;

    let width = frame.width as u32;
    let height = frame.height as u32;
    let frame_data = frame.data();

    let img = convert_bgra_to_rgba(frame_data, width, height)?;

    let saved_path = save_png(&img, &save_dir)?;

    if copy_to_clip {
        copy_to_clipboard(&img)?;
    }

    capturer.stop_capture();

    Ok(saved_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convert_bgra_to_rgba() {
        let width = 2;
        let height = 2;
        let bgra_data = vec![
            0xFF, 0x00, 0x00, 0xFF,
            0x00, 0xFF, 0x00, 0xFF,
            0x00, 0x00, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF,
        ];

        let result = convert_bgra_to_rgba(&bgra_data, width, height);
        assert!(result.is_ok());

        let img = result.unwrap();
        assert_eq!(img.width(), width);
        assert_eq!(img.height(), height);

        let pixel = img.get_pixel(0, 0);
        assert_eq!(pixel[0], 0x00);
        assert_eq!(pixel[1], 0x00);
        assert_eq!(pixel[2], 0xFF);
        assert_eq!(pixel[3], 0xFF);
    }

    #[test]
    fn test_convert_bgra_to_rgba_invalid_length() {
        let width = 2;
        let height = 2;
        let invalid_data = vec![0xFF; 8];

        let result = convert_bgra_to_rgba(&invalid_data, width, height);
        assert!(result.is_err());
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            #[cfg(desktop)]
            {
                use tauri_plugin_global_shortcut::{Code, Modifiers, Shortcut};
                let handle = app.handle().clone();
                let shortcut = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyS);
                
                if let Err(e) = handle
                    .plugin(tauri_plugin_global_shortcut::AppHandleExt::global_shortcut(&handle))
                    .register(shortcut, move || {
                        if let Err(err) = handle.emit("capture-triggered", ()) {
                            eprintln!("Failed to emit capture event: {:?}", err);
                        }
                    })
                {
                    eprintln!("Failed to register global shortcut: {:?}", e);
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![capture_once])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
